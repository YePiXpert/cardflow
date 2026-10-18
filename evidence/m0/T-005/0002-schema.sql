-- $ docker exec cardflow-dev-db-1 pg_dump -U cardflow --schema-only -d cardflow_test_t005_0002_evidence
-- (temporary database at head 0002, built by evidence/m0/T-005/0002-commands.sh; dropped afterwards)
--
-- PostgreSQL database dump
--

\restrict wGjMgueqooamoyIvRQ1LBqXRnl5bPqXiL7Pi7fDbd42DU3YGn7gOSWu8NuJ5SkJ

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.6 (Debian 18.6-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: add_to_repayment_allocation_total(uuid, uuid, bigint); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.add_to_repayment_allocation_total(p_workspace_id uuid, p_repayment_id uuid, p_delta bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    -- UPDATE first: INSERT ... ON CONFLICT would check allocated_minor >= 0 on the proposed
    -- row (a negative delta) before resolving the conflict.
    UPDATE public.repayment_allocation_totals AS t
       SET allocated_minor = t.allocated_minor + p_delta
     WHERE t.repayment_id = p_repayment_id;
    IF NOT FOUND THEN
        -- First allocation of this repayment (concurrent first inserts meet in ON CONFLICT).
        INSERT INTO public.repayment_allocation_totals AS t
               (repayment_id, workspace_id, allocated_minor)
        VALUES (p_repayment_id, p_workspace_id, p_delta)
        ON CONFLICT (repayment_id)
        DO UPDATE SET allocated_minor = t.allocated_minor + EXCLUDED.allocated_minor;
    END IF;
END
$$;


ALTER FUNCTION public.add_to_repayment_allocation_total(p_workspace_id uuid, p_repayment_id uuid, p_delta bigint) OWNER TO cardflow;

--
-- Name: bump_row_version(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.bump_row_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    NEW.row_version := OLD.row_version + 1;
    NEW.updated_at := now();
    RETURN NEW;
END
$$;


ALTER FUNCTION public.bump_row_version() OWNER TO cardflow;

--
-- Name: check_card_replacement_cycle(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_card_replacement_cycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.replaced_by_card_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE successors (id, replaced_by_card_id, depth) AS (
            SELECT c.id, c.replaced_by_card_id, 1
              FROM public.cards AS c
             WHERE c.id = NEW.replaced_by_card_id
            UNION ALL
            SELECT c.id, c.replaced_by_card_id, s.depth + 1
              FROM public.cards AS c
              JOIN successors AS s ON c.id = s.replaced_by_card_id
             WHERE s.depth < 1000
        )
        SELECT 1 FROM successors WHERE successors.id = NEW.id
    ) THEN
        RAISE EXCEPTION 'card replacement chain would contain a cycle'
            USING ERRCODE = 'check_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'replaced_by_card_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.check_card_replacement_cycle() OWNER TO cardflow;

--
-- Name: check_credit_pool_cycle(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_credit_pool_cycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.parent_pool_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE ancestors (id, parent_pool_id, depth) AS (
            SELECT p.id, p.parent_pool_id, 1
              FROM public.credit_pools AS p
             WHERE p.id = NEW.parent_pool_id
            UNION ALL
            SELECT p.id, p.parent_pool_id, a.depth + 1
              FROM public.credit_pools AS p
              JOIN ancestors AS a ON p.id = a.parent_pool_id
             WHERE a.depth < 1000
        )
        SELECT 1 FROM ancestors WHERE ancestors.id = NEW.id
    ) THEN
        RAISE EXCEPTION 'credit pool hierarchy would contain a cycle'
            USING ERRCODE = 'check_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'parent_pool_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.check_credit_pool_cycle() OWNER TO cardflow;

--
-- Name: check_repayment_allocations(uuid); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_repayment_allocations(p_repayment_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_amount bigint;
    v_status text;
    v_deleted_at timestamptz;
    v_allocated bigint;
BEGIN
    SELECT r.amount_minor, r.status, r.deleted_at
      INTO v_amount, v_status, v_deleted_at
      FROM public.repayments AS r
     WHERE r.id = p_repayment_id
       FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;  -- the repayment itself is gone; foreign keys report orphans
    END IF;

    UPDATE public.repayment_allocation_totals AS t
       SET allocated_minor = t.allocated_minor
     WHERE t.repayment_id = p_repayment_id
    RETURNING t.allocated_minor INTO v_allocated;
    v_allocated := coalesce(v_allocated, 0);

    IF v_allocated > v_amount THEN
        RAISE EXCEPTION 'repayment allocations exceed the repayment amount'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_within_amount';
    END IF;
    IF v_allocated > 0 AND (v_deleted_at IS NOT NULL OR v_status IN ('reversed', 'failed')) THEN
        RAISE EXCEPTION 'a deleted, reversed or failed repayment keeps no live allocations'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_inactive_repayment';
    END IF;
END
$$;


ALTER FUNCTION public.check_repayment_allocations(p_repayment_id uuid) OWNER TO cardflow;

--
-- Name: check_rule_subject_scope(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_rule_subject_scope() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NEW.subject_kind = 'product' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.card_products AS p
             WHERE p.id = NEW.subject_id
               AND (p.workspace_id IS NULL OR p.workspace_id = NEW.workspace_id)
        ) INTO v_ok;
    ELSIF NEW.subject_kind = 'credit_account' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.credit_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM public.currency_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    END IF;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'billing_rule_versions.subject_id: no % in this scope',
                        NEW.subject_kind
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'subject_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.check_rule_subject_scope() OWNER TO cardflow;

--
-- Name: check_statement_line_transaction(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_statement_line_transaction() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_xmin xid;
BEGIN
    SELECT v.xmin INTO v_xmin
      FROM public.statement_versions AS v
     WHERE v.id = NEW.statement_version_id;
    IF FOUND AND NOT public.inserted_by_current_transaction(v_xmin) THEN
        RAISE EXCEPTION 'statement lines are written in the transaction that creates their version'
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.check_statement_line_transaction() OWNER TO cardflow;

--
-- Name: check_template_scope(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_template_scope() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    v_column text := TG_ARGV[0];
    v_table text := TG_ARGV[1];
    v_ref uuid;
    v_ok boolean;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_column) INTO v_ref USING NEW;
    IF v_ref IS NULL THEN
        RETURN NEW;
    END IF;
    EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM public.%I AS t WHERE t.id = $1 '
        'AND (t.workspace_id IS NULL OR t.workspace_id = $2))', v_table)
        INTO v_ok USING v_ref, NEW.workspace_id;
    IF NOT v_ok THEN
        RAISE EXCEPTION '%.% must reference an official template or a row of the same workspace',
                        TG_TABLE_NAME, v_column
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = v_column,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$_$;


ALTER FUNCTION public.check_template_scope() OWNER TO cardflow;

--
-- Name: derive_from_parent(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.derive_from_parent() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    v_target text := TG_ARGV[0];
    v_parent text := TG_ARGV[1];
    v_key text := TG_ARGV[2];
    v_source text := TG_ARGV[3];
    v_key_value uuid;
    v_found boolean;
    v_value jsonb;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_key) INTO v_key_value USING NEW;
    EXECUTE format(
        'SELECT true, to_jsonb(p.%I) FROM public.%I AS p '
        'WHERE p.workspace_id = $1 AND p.id = $2', v_source, v_parent)
        INTO v_found, v_value USING NEW.workspace_id, v_key_value;
    IF v_found IS NULL THEN
        RAISE EXCEPTION '%.% does not reference a % row of the same workspace',
                        TG_TABLE_NAME, v_key, v_parent
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = v_key,
                  CONSTRAINT = TG_NAME;
    END IF;
    NEW := jsonb_populate_record(NEW, jsonb_build_object(v_target, v_value));
    RETURN NEW;
END
$_$;


ALTER FUNCTION public.derive_from_parent() OWNER TO cardflow;

--
-- Name: forbid_column_update(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_column_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_new jsonb := to_jsonb(NEW);
    v_old jsonb := to_jsonb(OLD);
    v_column text;
BEGIN
    FOREACH v_column IN ARRAY TG_ARGV LOOP
        IF v_new -> v_column IS DISTINCT FROM v_old -> v_column THEN
            RAISE EXCEPTION '%.% cannot change', TG_TABLE_NAME, v_column
                USING ERRCODE = 'integrity_constraint_violation',
                      TABLE = TG_TABLE_NAME,
                      COLUMN = v_column,
                      CONSTRAINT = TG_NAME;
        END IF;
    END LOOP;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.forbid_column_update() OWNER TO cardflow;

--
-- Name: forbid_fact_delete(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_fact_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF current_setting('app.purge', true) = pg_current_xact_id()::text THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION '% rows are never deleted; set deleted_at (tombstone) instead', TG_TABLE_NAME
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME,
              HINT = 'A workspace purge first runs '
                     || 'SELECT set_config(''app.purge'', pg_current_xact_id()::text, true).';
END
$$;


ALTER FUNCTION public.forbid_fact_delete() OWNER TO cardflow;

--
-- Name: forbid_fact_rewrite(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_fact_rewrite() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    -- The only permitted UPDATE is the tombstone itself: deleted_at goes from NULL to a
    -- value once, nothing else changes (row_version/updated_at are bumped by trigger).
    IF OLD.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION '% rows are frozen once tombstoned', TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    IF NEW.deleted_at IS NULL
       OR (to_jsonb(NEW) - ARRAY['deleted_at', 'row_version', 'updated_at'])
          IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['deleted_at', 'row_version', 'updated_at']) THEN
        RAISE EXCEPTION '% rows are immutable; only deleted_at may be set once (tombstone)',
                        TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.forbid_fact_rewrite() OWNER TO cardflow;

--
-- Name: forbid_workspace_change(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_workspace_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id THEN
        RAISE EXCEPTION '%.workspace_id cannot change', TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'workspace_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$;


ALTER FUNCTION public.forbid_workspace_change() OWNER TO cardflow;

--
-- Name: inserted_by_current_transaction(xid); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.inserted_by_current_transaction(p_xmin xid) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_reference bigint := pg_current_xact_id()::text::bigint;
    v_xmin bigint := p_xmin::text::bigint;
    v_full bigint;
BEGIN
    IF v_xmin < 3 THEN
        RETURN false;  -- invalid, bootstrap or frozen: never the current transaction
    END IF;
    v_full := ((v_reference >> 32) << 32) | v_xmin;
    IF v_full > v_reference + 2147483648 THEN
        v_full := v_full - 4294967296;
    ELSIF v_full < v_reference - 2147483648 THEN
        v_full := v_full + 4294967296;
    END IF;
    RETURN coalesce(pg_xact_status(v_full::text::xid8) = 'in progress', false);
END
$$;


ALTER FUNCTION public.inserted_by_current_transaction(p_xmin xid) OWNER TO cardflow;

--
-- Name: looks_like_pan(text); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.looks_like_pan(value text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT coalesce(bool_or(length(t.digits) BETWEEN 13 AND 19
                            AND public.luhn_valid(t.digits)), false)
      FROM (SELECT regexp_replace(m[1], '[ -]', '', 'g') AS digits
              FROM regexp_matches(coalesce(value, ''), '([0-9](?:[ -]?[0-9])*)', 'g') AS m) AS t
$$;


ALTER FUNCTION public.looks_like_pan(value text) OWNER TO cardflow;

--
-- Name: luhn_valid(text); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.luhn_valid(digits text) RETURNS boolean
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
    SELECT CASE
        WHEN digits !~ '^[0-9]+$' THEN false
        ELSE (
            SELECT sum(CASE WHEN d.i % 2 = 0
                            THEN (CASE WHEN d.digit * 2 > 9 THEN d.digit * 2 - 9
                                       ELSE d.digit * 2 END)
                            ELSE d.digit END) % 10 = 0
              FROM (SELECT i, substr(reverse(digits), i, 1)::int AS digit
                      FROM generate_series(1, length(digits)) AS i) AS d
        )
    END
$_$;


ALTER FUNCTION public.luhn_valid(digits text) OWNER TO cardflow;

--
-- Name: maintain_repayment_allocation_totals(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.maintain_repayment_allocation_totals() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
    v_old bigint := 0;
    v_new bigint := 0;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.deleted_at IS NULL THEN
            v_new := NEW.amount_minor;
        END IF;
        PERFORM public.add_to_repayment_allocation_total(
            NEW.workspace_id, NEW.repayment_id, v_new);
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.deleted_at IS NULL THEN
            v_old := OLD.amount_minor;
        END IF;
        PERFORM public.add_to_repayment_allocation_total(
            OLD.workspace_id, OLD.repayment_id, -v_old);
    ELSE
        IF OLD.deleted_at IS NULL THEN
            v_old := OLD.amount_minor;
        END IF;
        IF NEW.deleted_at IS NULL THEN
            v_new := NEW.amount_minor;
        END IF;
        IF OLD.repayment_id IS DISTINCT FROM NEW.repayment_id THEN
            PERFORM public.add_to_repayment_allocation_total(
                OLD.workspace_id, OLD.repayment_id, -v_old);
            PERFORM public.add_to_repayment_allocation_total(
                NEW.workspace_id, NEW.repayment_id, v_new);
        ELSE
            PERFORM public.add_to_repayment_allocation_total(
                NEW.workspace_id, NEW.repayment_id, v_new - v_old);
        END IF;
    END IF;
    RETURN NULL;
END
$$;


ALTER FUNCTION public.maintain_repayment_allocation_totals() OWNER TO cardflow;

--
-- Name: repayment_allocations_check(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.repayment_allocations_check() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM public.check_repayment_allocations(NEW.repayment_id);
    RETURN NULL;
END
$$;


ALTER FUNCTION public.repayment_allocations_check() OWNER TO cardflow;

--
-- Name: repayments_allocation_check(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.repayments_allocation_check() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM public.check_repayment_allocations(NEW.id);
    RETURN NULL;
END
$$;


ALTER FUNCTION public.repayments_allocation_check() OWNER TO cardflow;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


ALTER TABLE public.alembic_version OWNER TO cardflow;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid,
    actor_kind text NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    target_table text,
    target_id uuid,
    before_hash character(64),
    after_hash character(64),
    ip inet,
    at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_audit_log_after_hash_hex CHECK ((after_hash ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT ck_audit_log_before_hash_hex CHECK ((before_hash ~ '^[0-9a-f]{64}$'::text))
);


ALTER TABLE public.audit_log OWNER TO cardflow;

--
-- Name: COLUMN audit_log.actor_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.audit_log.actor_kind IS 'Open set (user, device, admin, system ...); no CHECK by design.';


--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.auth_sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    device_id uuid NOT NULL,
    refresh_token_hash character(64) NOT NULL,
    rotated_from_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoked_reason text,
    CONSTRAINT ck_auth_sessions_expires_after_created CHECK ((expires_at > created_at)),
    CONSTRAINT ck_auth_sessions_not_rotated_from_self CHECK (((rotated_from_id IS NULL) OR (rotated_from_id <> id))),
    CONSTRAINT ck_auth_sessions_reason_needs_revocation CHECK (((revoked_reason IS NULL) OR (revoked_at IS NOT NULL))),
    CONSTRAINT ck_auth_sessions_refresh_token_hash_hex CHECK ((refresh_token_hash ~ '^[0-9a-f]{64}$'::text))
);


ALTER TABLE public.auth_sessions OWNER TO cardflow;

--
-- Name: banks; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.banks (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid,
    name text NOT NULL,
    country character(2),
    business_tz_default text DEFAULT 'Asia/Shanghai'::text NOT NULL,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_banks_country_format CHECK ((country ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT ck_banks_name_not_pan CHECK ((NOT public.looks_like_pan(name)))
);


ALTER TABLE public.banks OWNER TO cardflow;

--
-- Name: billing_rule_versions; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.billing_rule_versions (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid,
    subject_kind text NOT NULL,
    subject_id uuid NOT NULL,
    statement_day smallint NOT NULL,
    statement_day_inclusive boolean DEFAULT true NOT NULL,
    due_kind text NOT NULL,
    due_day smallint,
    due_month_offset smallint DEFAULT 0 NOT NULL,
    due_days smallint,
    due_day_kind text DEFAULT 'calendar'::text NOT NULL,
    holiday_rollover text DEFAULT 'none'::text NOT NULL,
    cutoff_time time without time zone,
    cutoff_tz text,
    source text NOT NULL,
    published_on date,
    effective_from date NOT NULL,
    effective_to date,
    verified_on date,
    version integer NOT NULL,
    review_status text NOT NULL,
    exceptions text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_billing_rule_versions_cutoff_tz_needs_time CHECK (((cutoff_tz IS NULL) OR (cutoff_time IS NOT NULL))),
    CONSTRAINT ck_billing_rule_versions_due_day_kind CHECK ((due_day_kind = ANY (ARRAY['calendar'::text, 'business'::text]))),
    CONSTRAINT ck_billing_rule_versions_due_day_range CHECK (((due_day >= 1) AND (due_day <= 31))),
    CONSTRAINT ck_billing_rule_versions_due_days_range CHECK (((due_days >= 1) AND (due_days <= 60))),
    CONSTRAINT ck_billing_rule_versions_due_kind CHECK ((due_kind = ANY (ARRAY['fixed_day'::text, 'days_after_statement'::text]))),
    CONSTRAINT ck_billing_rule_versions_due_month_offset CHECK ((due_month_offset = ANY (ARRAY[0, 1, 2]))),
    CONSTRAINT ck_billing_rule_versions_due_rule_complete CHECK ((((due_kind = 'fixed_day'::text) AND (due_day IS NOT NULL)) OR ((due_kind = 'days_after_statement'::text) AND (due_days IS NOT NULL)))),
    CONSTRAINT ck_billing_rule_versions_effective_range CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT ck_billing_rule_versions_exceptions_not_pan CHECK ((NOT public.looks_like_pan(exceptions))),
    CONSTRAINT ck_billing_rule_versions_holiday_rollover CHECK ((holiday_rollover = ANY (ARRAY['none'::text, 'next_business_day'::text]))),
    CONSTRAINT ck_billing_rule_versions_review_status CHECK ((review_status = ANY (ARRAY['draft'::text, 'in_review'::text, 'verified'::text, 'published'::text, 'user_declared'::text, 'expired'::text]))),
    CONSTRAINT ck_billing_rule_versions_statement_day_range CHECK (((statement_day >= 1) AND (statement_day <= 31))),
    CONSTRAINT ck_billing_rule_versions_subject_kind CHECK ((subject_kind = ANY (ARRAY['product'::text, 'credit_account'::text, 'currency_account'::text]))),
    CONSTRAINT ck_billing_rule_versions_template_subject CHECK (((workspace_id IS NOT NULL) OR (subject_kind = 'product'::text))),
    CONSTRAINT ck_billing_rule_versions_user_declared_scope CHECK (((review_status <> 'user_declared'::text) OR (workspace_id IS NOT NULL))),
    CONSTRAINT ck_billing_rule_versions_version_positive CHECK ((version >= 1)),
    CONSTRAINT ck_billing_rule_versions_workspace_review_status CHECK (((workspace_id IS NULL) OR (review_status = ANY (ARRAY['draft'::text, 'user_declared'::text, 'expired'::text]))))
);


ALTER TABLE public.billing_rule_versions OWNER TO cardflow;

--
-- Name: card_products; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.card_products (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid,
    bank_id uuid NOT NULL,
    name text NOT NULL,
    network text,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_card_products_name_not_pan CHECK ((NOT public.looks_like_pan(name)))
);


ALTER TABLE public.card_products OWNER TO cardflow;

--
-- Name: cards; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.cards (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    credit_account_id uuid NOT NULL,
    last4 character(4) NOT NULL,
    network text,
    holder_kind text NOT NULL,
    status text NOT NULL,
    expires_ym character(7),
    replaced_by_card_id uuid,
    alias text,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_cards_alias_not_pan CHECK ((NOT public.looks_like_pan(alias))),
    CONSTRAINT ck_cards_expires_ym_format CHECK ((expires_ym ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'::text)),
    CONSTRAINT ck_cards_holder_kind CHECK ((holder_kind = ANY (ARRAY['primary'::text, 'supplementary'::text]))),
    CONSTRAINT ck_cards_last4_digits CHECK ((last4 ~ '^[0-9]{4}$'::text)),
    CONSTRAINT ck_cards_not_replaced_by_self CHECK (((replaced_by_card_id IS NULL) OR (replaced_by_card_id <> id))),
    CONSTRAINT ck_cards_status CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'frozen'::text, 'replaced'::text, 'closed'::text])))
);


ALTER TABLE public.cards OWNER TO cardflow;

--
-- Name: cash_accounts; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.cash_accounts (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    currency character(3) NOT NULL,
    kind text NOT NULL,
    usable_for_repayment boolean DEFAULT true NOT NULL,
    available_from date,
    reserve_floor_minor bigint DEFAULT 0 NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_cash_accounts_kind CHECK ((kind = ANY (ARRAY['bank'::text, 'wallet'::text, 'wealth'::text, 'restricted'::text]))),
    CONSTRAINT ck_cash_accounts_name_not_pan CHECK ((NOT public.looks_like_pan(name))),
    CONSTRAINT ck_cash_accounts_reserve_floor_non_negative CHECK ((reserve_floor_minor >= 0))
);


ALTER TABLE public.cash_accounts OWNER TO cardflow;

--
-- Name: cash_balance_snapshots; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.cash_balance_snapshots (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    cash_account_id uuid NOT NULL,
    balance_minor bigint NOT NULL,
    balance_as_of date NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_cash_balance_snapshots_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text])))
);


ALTER TABLE public.cash_balance_snapshots OWNER TO cardflow;

--
-- Name: COLUMN cash_balance_snapshots.source_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.cash_balance_snapshots.source_kind IS 'Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, import ...); no CHECK by design.';


--
-- Name: cash_events; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.cash_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    cash_account_id uuid NOT NULL,
    event_on date NOT NULL,
    event_at timestamp with time zone,
    amount_minor bigint NOT NULL,
    cls text NOT NULL,
    category text NOT NULL,
    label text,
    posting_status text NOT NULL,
    recurring_item_id uuid,
    linked_repayment_id uuid,
    linked_plan_run_id uuid,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    event_tz text,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_cash_events_amount_nonzero CHECK ((amount_minor <> 0)),
    CONSTRAINT ck_cash_events_amount_sign CHECK ((((category = ANY (ARRAY['income'::text, 'transfer_in'::text])) AND (amount_minor > 0)) OR ((category = ANY (ARRAY['bill'::text, 'living'::text, 'repayment'::text, 'transfer_out'::text, 'fee'::text])) AND (amount_minor < 0)) OR (category = 'other'::text))),
    CONSTRAINT ck_cash_events_category CHECK ((category = ANY (ARRAY['income'::text, 'bill'::text, 'living'::text, 'repayment'::text, 'transfer_in'::text, 'transfer_out'::text, 'fee'::text, 'other'::text]))),
    CONSTRAINT ck_cash_events_cls CHECK ((cls = ANY (ARRAY['confirmed'::text, 'expected'::text, 'planned'::text]))),
    CONSTRAINT ck_cash_events_event_at_needs_tz CHECK (((event_at IS NULL) OR (event_tz IS NOT NULL))),
    CONSTRAINT ck_cash_events_label_not_pan CHECK ((NOT public.looks_like_pan(label))),
    CONSTRAINT ck_cash_events_posting_status CHECK ((posting_status = ANY (ARRAY['planned'::text, 'posted'::text])))
);


ALTER TABLE public.cash_events OWNER TO cardflow;

--
-- Name: COLUMN cash_events.amount_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.cash_events.amount_minor IS 'Minor units of the cash account''s currency, never 0. Positive = inflow (income, transfer_in); negative = outflow (bill, living, repayment, transfer_out, fee); other: either sign.';


--
-- Name: cash_transfers; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.cash_transfers (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    from_cash_account_id uuid NOT NULL,
    to_cash_account_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    sent_on date NOT NULL,
    arrives_on date,
    out_event_id uuid,
    in_event_id uuid,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_cash_transfers_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_cash_transfers_arrives_after_sent CHECK (((arrives_on IS NULL) OR (arrives_on >= sent_on))),
    CONSTRAINT ck_cash_transfers_distinct_accounts CHECK ((from_cash_account_id <> to_cash_account_id))
);


ALTER TABLE public.cash_transfers OWNER TO cardflow;

--
-- Name: charges; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.charges (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    statement_id uuid,
    transaction_id uuid,
    kind text NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    charged_on date NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_kind text NOT NULL,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_charges_amount_nonzero CHECK ((amount_minor <> 0)),
    CONSTRAINT ck_charges_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text])))
);


ALTER TABLE public.charges OWNER TO cardflow;

--
-- Name: COLUMN charges.kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.charges.kind IS 'Open set (annual_fee, cash_advance_fee, fx_fee, interest, late_fee, installment_fee, other ...); no CHECK by design.';


--
-- Name: COLUMN charges.amount_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.charges.amount_minor IS 'Minor units, never 0. Positive = fee or interest charged; negative = waiver or refund of a charge.';


--
-- Name: COLUMN charges.source_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.charges.source_kind IS 'Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, import ...); no CHECK by design.';


--
-- Name: consents; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.consents (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    purpose text NOT NULL,
    granted_at timestamp with time zone NOT NULL,
    withdrawn_at timestamp with time zone,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_consents_withdrawn_after_granted CHECK (((withdrawn_at IS NULL) OR (withdrawn_at >= granted_at)))
);


ALTER TABLE public.consents OWNER TO cardflow;

--
-- Name: COLUMN consents.purpose; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.consents.purpose IS 'Open set (ai_extract, gmail, server_sync, analytics ...), data-model §3; no CHECK by design.';


--
-- Name: credit_accounts; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.credit_accounts (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    bank_id uuid NOT NULL,
    product_id uuid,
    holder_alias text NOT NULL,
    business_tz text DEFAULT 'Asia/Shanghai'::text NOT NULL,
    status text NOT NULL,
    opened_on date,
    closed_on date,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_credit_accounts_closed_after_opened CHECK (((closed_on IS NULL) OR (opened_on IS NULL) OR (closed_on >= opened_on))),
    CONSTRAINT ck_credit_accounts_holder_alias_not_pan CHECK ((NOT public.looks_like_pan(holder_alias))),
    CONSTRAINT ck_credit_accounts_status CHECK ((status = ANY (ARRAY['active'::text, 'frozen'::text, 'closed'::text])))
);


ALTER TABLE public.credit_accounts OWNER TO cardflow;

--
-- Name: credit_pool_members; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.credit_pool_members (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    pool_id uuid NOT NULL,
    credit_account_id uuid NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid
);


ALTER TABLE public.credit_pool_members OWNER TO cardflow;

--
-- Name: credit_pools; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.credit_pools (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    bank_id uuid NOT NULL,
    name text NOT NULL,
    parent_pool_id uuid,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_credit_pools_name_not_pan CHECK ((NOT public.looks_like_pan(name))),
    CONSTRAINT ck_credit_pools_not_own_parent CHECK (((parent_pool_id IS NULL) OR (parent_pool_id <> id)))
);


ALTER TABLE public.credit_pools OWNER TO cardflow;

--
-- Name: currencies; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.currencies (
    code character(3) NOT NULL,
    minor_digits smallint NOT NULL,
    CONSTRAINT ck_currencies_code_format CHECK ((code ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT ck_currencies_minor_digits_range CHECK (((minor_digits >= 0) AND (minor_digits <= 3)))
);


ALTER TABLE public.currencies OWNER TO cardflow;

--
-- Name: currency_accounts; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.currency_accounts (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    credit_account_id uuid NOT NULL,
    currency character(3) NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid
);


ALTER TABLE public.currency_accounts OWNER TO cardflow;

--
-- Name: dedupe_keys; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.dedupe_keys (
    workspace_id uuid NOT NULL,
    key_hash character(64) NOT NULL,
    entity_kind text NOT NULL,
    entity_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_dedupe_keys_key_hash_hex CHECK ((key_hash ~ '^[0-9a-f]{64}$'::text))
);


ALTER TABLE public.dedupe_keys OWNER TO cardflow;

--
-- Name: COLUMN dedupe_keys.entity_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.dedupe_keys.entity_kind IS 'Table name of the deduplicated entity; no CHECK by design.';


--
-- Name: deletion_tasks; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.deletion_tasks (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    grace_until timestamp with time zone NOT NULL,
    status text NOT NULL,
    executed_at timestamp with time zone,
    CONSTRAINT ck_deletion_tasks_grace_after_request CHECK ((grace_until >= requested_at)),
    CONSTRAINT ck_deletion_tasks_status CHECK ((status = ANY (ARRAY['pending'::text, 'cancelled'::text, 'executing'::text, 'executed'::text, 'failed'::text])))
);


ALTER TABLE public.deletion_tasks OWNER TO cardflow;

--
-- Name: devices; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.devices (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid,
    name text,
    platform text NOT NULL,
    public_key bytea NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone,
    revoked_at timestamp with time zone,
    CONSTRAINT ck_devices_name_not_pan CHECK ((NOT public.looks_like_pan(name))),
    CONSTRAINT ck_devices_public_key_length CHECK (((octet_length(public_key) >= 32) AND (octet_length(public_key) <= 4096)))
);


ALTER TABLE public.devices OWNER TO cardflow;

--
-- Name: COLUMN devices.platform; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.devices.platform IS 'Open set (ios, android ...); no CHECK by design.';


--
-- Name: extraction_candidates; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.extraction_candidates (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    parse_job_id uuid NOT NULL,
    field_path text NOT NULL,
    raw_value text,
    normalized_value text,
    raw_location jsonb NOT NULL,
    parser_version text NOT NULL,
    confidence numeric(5,4) NOT NULL,
    validations jsonb DEFAULT '[]'::jsonb NOT NULL,
    confirmed_value text,
    confirmed_by text,
    confirmed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_extraction_candidates_confidence_range CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
    CONSTRAINT ck_extraction_candidates_values_not_pan CHECK (((field_path ~ '(^|[.])bank_reference$'::text) OR (NOT (public.looks_like_pan(raw_value) OR public.looks_like_pan(normalized_value) OR public.looks_like_pan(confirmed_value)))))
);


ALTER TABLE public.extraction_candidates OWNER TO cardflow;

--
-- Name: forecast_runs; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.forecast_runs (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    scenario_id uuid NOT NULL,
    horizon_start date NOT NULL,
    horizon_end date NOT NULL,
    input_hash text NOT NULL,
    model_version text NOT NULL,
    protocol_version text,
    computed_locally boolean DEFAULT false NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_forecast_runs_horizon_order CHECK ((horizon_end >= horizon_start))
);


ALTER TABLE public.forecast_runs OWNER TO cardflow;

--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.idempotency_keys (
    workspace_id uuid NOT NULL,
    key text NOT NULL,
    request_hash character(64) NOT NULL,
    response_status smallint NOT NULL,
    response_body jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_idempotency_keys_request_hash_hex CHECK ((request_hash ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT ck_idempotency_keys_response_status_range CHECK (((response_status >= 100) AND (response_status <= 599)))
);


ALTER TABLE public.idempotency_keys OWNER TO cardflow;

--
-- Name: import_batch_items; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.import_batch_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    import_batch_id uuid NOT NULL,
    item_no integer NOT NULL,
    entity_kind text NOT NULL,
    candidate_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
    decision text,
    duplicate_of_id uuid,
    resulting_entity_kind text,
    resulting_entity_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_import_batch_items_decision CHECK ((decision = ANY (ARRAY['new'::text, 'duplicate'::text, 'new_version'::text, 'skip'::text]))),
    CONSTRAINT ck_import_batch_items_duplicate_needs_target CHECK (((decision IS DISTINCT FROM 'duplicate'::text) OR (duplicate_of_id IS NOT NULL))),
    CONSTRAINT ck_import_batch_items_item_no_positive CHECK ((item_no >= 1)),
    CONSTRAINT ck_import_batch_items_resulting_entity_pair CHECK (((resulting_entity_kind IS NULL) = (resulting_entity_id IS NULL)))
);


ALTER TABLE public.import_batch_items OWNER TO cardflow;

--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.import_batches (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    kind text NOT NULL,
    status text NOT NULL,
    target_currency_account_id uuid,
    source_document_id uuid,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_at timestamp with time zone,
    posted_at timestamp with time zone,
    rolled_back_at timestamp with time zone,
    CONSTRAINT ck_import_batches_failure_reason_not_pan CHECK ((NOT public.looks_like_pan(failure_reason))),
    CONSTRAINT ck_import_batches_status CHECK ((status = ANY (ARRAY['uploaded'::text, 'parsing'::text, 'needs_review'::text, 'confirmed'::text, 'posted'::text, 'failed'::text, 'rolled_back'::text])))
);


ALTER TABLE public.import_batches OWNER TO cardflow;

--
-- Name: COLUMN import_batches.kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.import_batches.kind IS 'Open set of import channels (csv, pdf, text, screenshot, eml, html, sms ...); no CHECK by design.';


--
-- Name: installment_plans; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.installment_plans (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    transaction_id uuid NOT NULL,
    principal_minor bigint NOT NULL,
    periods smallint NOT NULL,
    per_period_rate numeric(20,10) NOT NULL,
    fee_mode text NOT NULL,
    remainder_policy text DEFAULT 'last'::text NOT NULL,
    rounding text DEFAULT 'HALF_UP'::text NOT NULL,
    status text NOT NULL,
    early_settled_at timestamp with time zone,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_installment_plans_fee_mode CHECK ((fee_mode = ANY (ARRAY['per_period'::text, 'upfront'::text]))),
    CONSTRAINT ck_installment_plans_periods_positive CHECK ((periods >= 1)),
    CONSTRAINT ck_installment_plans_principal_positive CHECK ((principal_minor > 0)),
    CONSTRAINT ck_installment_plans_rate_non_negative CHECK ((per_period_rate >= (0)::numeric)),
    CONSTRAINT ck_installment_plans_remainder_policy CHECK ((remainder_policy = ANY (ARRAY['last'::text, 'first'::text]))),
    CONSTRAINT ck_installment_plans_rounding CHECK ((rounding = ANY (ARRAY['HALF_UP'::text, 'DOWN'::text, 'HALF_EVEN'::text, 'UP'::text]))),
    CONSTRAINT ck_installment_plans_status CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'early_settled'::text, 'cancelled'::text])))
);


ALTER TABLE public.installment_plans OWNER TO cardflow;

--
-- Name: installment_schedule; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.installment_schedule (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    period_no smallint NOT NULL,
    principal_minor bigint NOT NULL,
    interest_minor bigint DEFAULT 0 NOT NULL,
    statement_date date NOT NULL,
    due_date date NOT NULL,
    status text NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_installment_schedule_due_after_statement CHECK ((due_date > statement_date)),
    CONSTRAINT ck_installment_schedule_interest_non_negative CHECK ((interest_minor >= 0)),
    CONSTRAINT ck_installment_schedule_period_no_positive CHECK ((period_no >= 1)),
    CONSTRAINT ck_installment_schedule_principal_non_negative CHECK ((principal_minor >= 0)),
    CONSTRAINT ck_installment_schedule_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'billed'::text, 'settled'::text, 'cancelled'::text])))
);


ALTER TABLE public.installment_schedule OWNER TO cardflow;

--
-- Name: jobs; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.jobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    kind text NOT NULL,
    payload jsonb NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    run_after timestamp with time zone DEFAULT now() NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 5 NOT NULL,
    locked_by text,
    locked_until timestamp with time zone,
    heartbeat_at timestamp with time zone,
    timeout_s integer,
    last_error text,
    result jsonb,
    workspace_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    dedupe_key text,
    CONSTRAINT ck_jobs_attempts_non_negative CHECK ((attempts >= 0)),
    CONSTRAINT ck_jobs_max_attempts_positive CHECK ((max_attempts >= 1)),
    CONSTRAINT ck_jobs_running_has_lease CHECK (((status <> 'running'::text) OR ((locked_by IS NOT NULL) AND (locked_until IS NOT NULL)))),
    CONSTRAINT ck_jobs_status CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'dead'::text, 'canceled'::text]))),
    CONSTRAINT ck_jobs_timeout_positive CHECK ((timeout_s > 0))
);


ALTER TABLE public.jobs OWNER TO cardflow;

--
-- Name: COLUMN jobs.kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.jobs.kind IS 'Job type registered by the worker; no CHECK by design.';


--
-- Name: COLUMN jobs.dedupe_key; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.jobs.dedupe_key IS 'Optional key; at most one queued or running job per key (e.g. one periodic tick).';


--
-- Name: limit_adjustments; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.limit_adjustments (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    kind text NOT NULL,
    previous_limit_minor bigint,
    new_limit_minor bigint NOT NULL,
    effective_on date NOT NULL,
    expires_on date,
    purpose text,
    source_kind text NOT NULL,
    source_document_id uuid,
    observed_at timestamp with time zone,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmation_level text NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_limit_adjustments_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_limit_adjustments_expires_after_effective CHECK (((expires_on IS NULL) OR (expires_on > effective_on))),
    CONSTRAINT ck_limit_adjustments_kind CHECK ((kind = ANY (ARRAY['fixed'::text, 'temp'::text, 'special'::text]))),
    CONSTRAINT ck_limit_adjustments_new_limit_non_negative CHECK ((new_limit_minor >= 0)),
    CONSTRAINT ck_limit_adjustments_purpose_not_pan CHECK ((NOT public.looks_like_pan(purpose))),
    CONSTRAINT ck_limit_adjustments_source_kind CHECK ((source_kind = ANY (ARRAY['bank_app'::text, 'statement'::text, 'user'::text, 'import'::text])))
);


ALTER TABLE public.limit_adjustments OWNER TO cardflow;

--
-- Name: limit_snapshots; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.limit_snapshots (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    fixed_minor bigint NOT NULL,
    temp_minor bigint DEFAULT 0 NOT NULL,
    temp_expires_on date,
    special_minor bigint DEFAULT 0 NOT NULL,
    special_purpose text,
    used_minor bigint NOT NULL,
    available_raw_minor bigint NOT NULL,
    includes_holds boolean NOT NULL,
    source_kind text NOT NULL,
    source_document_id uuid,
    balance_as_of timestamp with time zone NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmation_level text NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_limit_snapshots_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_limit_snapshots_source_kind CHECK ((source_kind = ANY (ARRAY['bank_app'::text, 'statement'::text, 'user'::text, 'import'::text]))),
    CONSTRAINT ck_limit_snapshots_special_purpose_not_pan CHECK ((NOT public.looks_like_pan(special_purpose)))
);


ALTER TABLE public.limit_snapshots OWNER TO cardflow;

--
-- Name: COLUMN limit_snapshots.available_raw_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.limit_snapshots.available_raw_minor IS 'Available limit exactly as the bank reports it; may be negative (over limit). Only the derived capacity for new spend is clamped at zero.';


--
-- Name: parse_jobs; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.parse_jobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    source_document_id uuid NOT NULL,
    import_batch_id uuid,
    job_id uuid,
    parser text,
    parser_version text,
    status text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    failure_reason text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_parse_jobs_attempts_non_negative CHECK ((attempts >= 0)),
    CONSTRAINT ck_parse_jobs_failure_reason_not_pan CHECK ((NOT public.looks_like_pan(failure_reason))),
    CONSTRAINT ck_parse_jobs_status CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'quarantined'::text])))
);


ALTER TABLE public.parse_jobs OWNER TO cardflow;

--
-- Name: plan_allocations; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plan_allocations (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    run_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    card_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    statement_date date NOT NULL,
    due_date date NOT NULL,
    repay_on date NOT NULL,
    repay_from_cash_account_id uuid NOT NULL,
    buffer_days integer NOT NULL,
    fee_minor bigint DEFAULT 0 NOT NULL,
    verified_benefit_minor bigint DEFAULT 0 NOT NULL,
    potential_benefit_minor bigint DEFAULT 0 NOT NULL,
    cycle_assumptions jsonb DEFAULT '[]'::jsonb NOT NULL,
    alternative_cycles jsonb DEFAULT '[]'::jsonb NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency character(3) NOT NULL,
    credit_account_id uuid NOT NULL,
    CONSTRAINT ck_plan_allocations_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_plan_allocations_due_after_statement CHECK ((due_date > statement_date)),
    CONSTRAINT ck_plan_allocations_fee_non_negative CHECK ((fee_minor >= 0)),
    CONSTRAINT ck_plan_allocations_potential_benefit_non_negative CHECK ((potential_benefit_minor >= 0)),
    CONSTRAINT ck_plan_allocations_verified_benefit_non_negative CHECK ((verified_benefit_minor >= 0))
);


ALTER TABLE public.plan_allocations OWNER TO cardflow;

--
-- Name: COLUMN plan_allocations.currency; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.plan_allocations.currency IS 'Derived from run_id by trigger; clients do not supply it.';


--
-- Name: COLUMN plan_allocations.credit_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.plan_allocations.credit_account_id IS 'Derived from currency_account_id by trigger; clients do not supply it.';


--
-- Name: plan_invalidations; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plan_invalidations (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    run_id uuid,
    cause text NOT NULL,
    caused_by_table text,
    caused_by_id uuid,
    invalidated_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid
);


ALTER TABLE public.plan_invalidations OWNER TO cardflow;

--
-- Name: COLUMN plan_invalidations.cause; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.plan_invalidations.cause IS 'Open set (snapshot_changed, cash_event_changed, rule_changed, manual ...); no CHECK by design.';


--
-- Name: plan_reservations; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plan_reservations (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    run_id uuid,
    currency_account_id uuid NOT NULL,
    cash_account_id uuid,
    amount_minor bigint NOT NULL,
    status text NOT NULL,
    linked_transaction_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency character(3) NOT NULL,
    CONSTRAINT ck_plan_reservations_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_plan_reservations_converted_needs_transaction CHECK (((status <> 'converted'::text) OR (linked_transaction_id IS NOT NULL))),
    CONSTRAINT ck_plan_reservations_status CHECK ((status = ANY (ARRAY['active'::text, 'converted'::text, 'released'::text])))
);


ALTER TABLE public.plan_reservations OWNER TO cardflow;

--
-- Name: COLUMN plan_reservations.currency; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.plan_reservations.currency IS 'Derived from plan_id by trigger; clients do not supply it.';


--
-- Name: plan_run_checks; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plan_run_checks (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    run_id uuid NOT NULL,
    scenario_id uuid NOT NULL,
    ok boolean NOT NULL,
    ok_zero boolean NOT NULL,
    min_balance_by_account jsonb NOT NULL,
    min_on_by_account jsonb DEFAULT '{}'::jsonb NOT NULL,
    breaches jsonb DEFAULT '[]'::jsonb NOT NULL,
    assumptions jsonb DEFAULT '[]'::jsonb NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid
);


ALTER TABLE public.plan_run_checks OWNER TO cardflow;

--
-- Name: plan_runs; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plan_runs (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    job_id uuid,
    profile text NOT NULL,
    decision_scenario_id uuid NOT NULL,
    solver_status text NOT NULL,
    business_status text NOT NULL,
    input_hash text NOT NULL,
    model_version text NOT NULL,
    solver_version text NOT NULL,
    protocol_version text NOT NULL,
    time_limit_s numeric(8,3) NOT NULL,
    workers smallint NOT NULL,
    seed integer NOT NULL,
    wall_time_s numeric(10,3),
    reserve_override_minor bigint,
    computed_locally boolean DEFAULT false NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency character(3) NOT NULL,
    CONSTRAINT ck_plan_runs_business_status CHECK ((business_status = ANY (ARRAY['NEEDS_DATA'::text, 'MODEL_INVALID'::text, 'BASELINE_SHORTFALL'::text, 'INFEASIBLE'::text, 'UNKNOWN'::text, 'FEASIBLE_ROBUST'::text, 'CONDITIONALLY_FEASIBLE'::text]))),
    CONSTRAINT ck_plan_runs_profile CHECK ((profile = ANY (ARRAY['cash_safety'::text, 'verified_benefit'::text, 'fewer_cards'::text]))),
    CONSTRAINT ck_plan_runs_reserve_override_non_negative CHECK ((reserve_override_minor >= 0)),
    CONSTRAINT ck_plan_runs_solver_status CHECK ((solver_status = ANY (ARRAY['OPTIMAL'::text, 'FEASIBLE'::text, 'INFEASIBLE'::text, 'UNKNOWN'::text, 'MODEL_INVALID'::text, 'NOT_RUN'::text]))),
    CONSTRAINT ck_plan_runs_time_limit_positive CHECK ((time_limit_s > (0)::numeric)),
    CONSTRAINT ck_plan_runs_wall_time_non_negative CHECK ((wall_time_s >= (0)::numeric)),
    CONSTRAINT ck_plan_runs_workers_positive CHECK ((workers >= 1))
);


ALTER TABLE public.plan_runs OWNER TO cardflow;

--
-- Name: COLUMN plan_runs.currency; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.plan_runs.currency IS 'Derived from plan_id by trigger; clients do not supply it.';


--
-- Name: plans; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.plans (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    txn_date date NOT NULL,
    allow_split boolean DEFAULT false NOT NULL,
    max_cards smallint DEFAULT 1 NOT NULL,
    min_split_minor bigint DEFAULT 1 NOT NULL,
    payment_lead_days smallint DEFAULT 0 NOT NULL,
    channel text NOT NULL,
    merchant text,
    category text,
    allow_installment boolean DEFAULT false NOT NULL,
    status text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_plans_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_plans_category_not_pan CHECK ((NOT public.looks_like_pan(category))),
    CONSTRAINT ck_plans_max_cards_positive CHECK ((max_cards >= 1)),
    CONSTRAINT ck_plans_merchant_not_pan CHECK ((NOT public.looks_like_pan(merchant))),
    CONSTRAINT ck_plans_min_split_positive CHECK ((min_split_minor >= 1)),
    CONSTRAINT ck_plans_payment_lead_days_non_negative CHECK ((payment_lead_days >= 0)),
    CONSTRAINT ck_plans_status CHECK ((status = ANY (ARRAY['draft'::text, 'solving'::text, 'solved'::text, 'infeasible'::text, 'unknown'::text, 'needs_data'::text, 'baseline_shortfall'::text, 'model_invalid'::text, 'adopted'::text, 'linked'::text, 'stale'::text, 'cancelled'::text])))
);


ALTER TABLE public.plans OWNER TO cardflow;

--
-- Name: preauth_holds; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.preauth_holds (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    card_id uuid,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    held_at timestamp with time zone NOT NULL,
    held_tz text NOT NULL,
    time_precision text NOT NULL,
    expected_release_on date,
    merchant text,
    status text NOT NULL,
    transaction_id uuid,
    source_kind text NOT NULL,
    source_document_id uuid,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    credit_account_id uuid NOT NULL,
    CONSTRAINT ck_preauth_holds_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_preauth_holds_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_preauth_holds_merchant_not_pan CHECK ((NOT public.looks_like_pan(merchant))),
    CONSTRAINT ck_preauth_holds_status CHECK ((status = ANY (ARRAY['active'::text, 'captured'::text, 'released'::text, 'expired'::text]))),
    CONSTRAINT ck_preauth_holds_time_precision CHECK ((time_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text])))
);


ALTER TABLE public.preauth_holds OWNER TO cardflow;

--
-- Name: COLUMN preauth_holds.source_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.preauth_holds.source_kind IS 'Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, import ...); no CHECK by design.';


--
-- Name: COLUMN preauth_holds.credit_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.preauth_holds.credit_account_id IS 'Derived from currency_account_id by trigger; clients do not supply it.';


--
-- Name: reconciliation_items; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.reconciliation_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    kind text NOT NULL,
    refs jsonb NOT NULL,
    status text NOT NULL,
    source_kind text,
    suggested_action text,
    resolution text,
    resolved_by text,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_reconciliation_items_kind CHECK ((kind = ANY (ARRAY['amount_mismatch'::text, 'missing'::text, 'duplicate_txn'::text, 'duplicate_repayment'::text, 'refund_pending'::text, 'unmatched_repayment'::text, 'sync_conflict'::text]))),
    CONSTRAINT ck_reconciliation_items_resolution_not_pan CHECK ((NOT public.looks_like_pan(resolution))),
    CONSTRAINT ck_reconciliation_items_status CHECK ((status = ANY (ARRAY['open'::text, 'resolved'::text, 'dismissed'::text]))),
    CONSTRAINT ck_reconciliation_items_suggested_action_not_pan CHECK ((NOT public.looks_like_pan(suggested_action)))
);


ALTER TABLE public.reconciliation_items OWNER TO cardflow;

--
-- Name: COLUMN reconciliation_items.source_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.reconciliation_items.source_kind IS 'Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, import ...); no CHECK by design.';


--
-- Name: recurring_items; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.recurring_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    cash_account_id uuid NOT NULL,
    label text NOT NULL,
    category text NOT NULL,
    amount_minor bigint NOT NULL,
    cls text NOT NULL,
    recurrence jsonb NOT NULL,
    starts_on date NOT NULL,
    ends_on date,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_recurring_items_amount_nonzero CHECK ((amount_minor <> 0)),
    CONSTRAINT ck_recurring_items_amount_sign CHECK ((((category = ANY (ARRAY['income'::text, 'transfer_in'::text])) AND (amount_minor > 0)) OR ((category = ANY (ARRAY['bill'::text, 'living'::text, 'repayment'::text, 'transfer_out'::text, 'fee'::text])) AND (amount_minor < 0)) OR (category = 'other'::text))),
    CONSTRAINT ck_recurring_items_category CHECK ((category = ANY (ARRAY['income'::text, 'bill'::text, 'living'::text, 'repayment'::text, 'transfer_in'::text, 'transfer_out'::text, 'fee'::text, 'other'::text]))),
    CONSTRAINT ck_recurring_items_cls CHECK ((cls = ANY (ARRAY['confirmed'::text, 'expected'::text, 'planned'::text]))),
    CONSTRAINT ck_recurring_items_ends_after_start CHECK (((ends_on IS NULL) OR (ends_on >= starts_on))),
    CONSTRAINT ck_recurring_items_label_not_pan CHECK ((NOT public.looks_like_pan(label)))
);


ALTER TABLE public.recurring_items OWNER TO cardflow;

--
-- Name: COLUMN recurring_items.amount_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.recurring_items.amount_minor IS 'Minor units per occurrence; same sign convention as cash_events.amount_minor.';


--
-- Name: repayment_allocation_totals; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.repayment_allocation_totals (
    repayment_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    allocated_minor bigint DEFAULT 0 NOT NULL,
    CONSTRAINT ck_repayment_allocation_totals_allocated_non_negative CHECK ((allocated_minor >= 0))
);


ALTER TABLE public.repayment_allocation_totals OWNER TO cardflow;

--
-- Name: repayment_allocations; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.repayment_allocations (
    id uuid DEFAULT uuidv7() NOT NULL,
    repayment_id uuid NOT NULL,
    statement_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency_account_id uuid NOT NULL,
    CONSTRAINT ck_repayment_allocations_amount_positive CHECK ((amount_minor > 0))
);


ALTER TABLE public.repayment_allocations OWNER TO cardflow;

--
-- Name: COLUMN repayment_allocations.currency_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.repayment_allocations.currency_account_id IS 'Derived from repayment_id by trigger; clients do not supply it.';


--
-- Name: repayments; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.repayments (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    cash_account_id uuid,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    status text NOT NULL,
    method text,
    payment_initiated_at timestamp with time zone,
    cash_debited_at timestamp with time zone,
    credit_posted_at timestamp with time zone,
    bank_confirmed_at timestamp with time zone,
    evidence_document_id uuid,
    origin_device_id uuid,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    event_tz text,
    cash_debited_precision text,
    credit_posted_precision text,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_repayments_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_repayments_bank_confirmed_needs_timestamp CHECK (((status <> 'bank_confirmed'::text) OR (bank_confirmed_at IS NOT NULL))),
    CONSTRAINT ck_repayments_cash_debited_precision CHECK ((cash_debited_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text]))),
    CONSTRAINT ck_repayments_cash_debited_precision_pair CHECK (((cash_debited_at IS NULL) = (cash_debited_precision IS NULL))),
    CONSTRAINT ck_repayments_credit_posted_precision CHECK ((credit_posted_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text]))),
    CONSTRAINT ck_repayments_credit_posted_precision_pair CHECK (((credit_posted_at IS NULL) = (credit_posted_precision IS NULL))),
    CONSTRAINT ck_repayments_status CHECK ((status = ANY (ARRAY['recorded'::text, 'processing'::text, 'cash_debited'::text, 'credit_posted'::text, 'bank_confirmed'::text, 'failed'::text, 'user_marked_paid'::text, 'needs_review'::text, 'reversed'::text]))),
    CONSTRAINT ck_repayments_times_need_tz CHECK (((event_tz IS NOT NULL) OR ((payment_initiated_at IS NULL) AND (cash_debited_at IS NULL) AND (credit_posted_at IS NULL) AND (bank_confirmed_at IS NULL))))
);


ALTER TABLE public.repayments OWNER TO cardflow;

--
-- Name: rule_bindings; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.rule_bindings (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    credit_account_id uuid NOT NULL,
    currency_account_id uuid,
    billing_rule_version_id uuid NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_rule_bindings_effective_range CHECK (((effective_to IS NULL) OR (effective_to > effective_from)))
);


ALTER TABLE public.rule_bindings OWNER TO cardflow;

--
-- Name: scenarios; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.scenarios (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    include_expected boolean DEFAULT true NOT NULL,
    income_delay_days integer DEFAULT 0 NOT NULL,
    income_scale numeric(20,10) DEFAULT 1 NOT NULL,
    expense_scale numeric(20,10) DEFAULT 1 NOT NULL,
    event_overrides jsonb DEFAULT '{}'::jsonb NOT NULL,
    same_day_order text DEFAULT 'conservative'::text NOT NULL,
    description text,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_scenarios_description_not_pan CHECK ((NOT public.looks_like_pan(description))),
    CONSTRAINT ck_scenarios_expense_scale_non_negative CHECK ((expense_scale >= (0)::numeric)),
    CONSTRAINT ck_scenarios_income_scale_non_negative CHECK ((income_scale >= (0)::numeric)),
    CONSTRAINT ck_scenarios_name_not_pan CHECK ((NOT public.looks_like_pan(name))),
    CONSTRAINT ck_scenarios_same_day_order CHECK ((same_day_order = ANY (ARRAY['conservative'::text, 'timestamp'::text])))
);


ALTER TABLE public.scenarios OWNER TO cardflow;

--
-- Name: snapshot_included_events; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.snapshot_included_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    snapshot_id uuid NOT NULL,
    cash_event_id uuid NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    cash_account_id uuid NOT NULL
);


ALTER TABLE public.snapshot_included_events OWNER TO cardflow;

--
-- Name: COLUMN snapshot_included_events.cash_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.snapshot_included_events.cash_account_id IS 'Derived from snapshot_id by trigger; clients do not supply it.';


--
-- Name: source_documents; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.source_documents (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    sha256 character(64) NOT NULL,
    mime text NOT NULL,
    size_bytes bigint NOT NULL,
    storage_key text,
    dek_wrapped bytea,
    uploaded_by_device_id uuid,
    retention_until date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    origin_device_id uuid,
    CONSTRAINT ck_source_documents_blob_while_live CHECK (((deleted_at IS NOT NULL) OR ((storage_key IS NOT NULL) AND (dek_wrapped IS NOT NULL)))),
    CONSTRAINT ck_source_documents_sha256_hex CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT ck_source_documents_size_limit CHECK (((size_bytes > 0) AND (size_bytes <= 26214400)))
);


ALTER TABLE public.source_documents OWNER TO cardflow;

--
-- Name: statement_attributions; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.statement_attributions (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    transaction_id uuid NOT NULL,
    statement_id uuid NOT NULL,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency_account_id uuid NOT NULL,
    CONSTRAINT ck_statement_attributions_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text])))
);


ALTER TABLE public.statement_attributions OWNER TO cardflow;

--
-- Name: COLUMN statement_attributions.currency_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.statement_attributions.currency_account_id IS 'Derived from transaction_id by trigger; clients do not supply it.';


--
-- Name: statement_lines; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.statement_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    statement_version_id uuid NOT NULL,
    line_no integer NOT NULL,
    kind text NOT NULL,
    description text,
    txn_on date,
    posted_on date,
    amount_minor bigint NOT NULL,
    card_last4 character(4),
    transaction_id uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency_account_id uuid NOT NULL,
    CONSTRAINT ck_statement_lines_card_last4_digits CHECK ((card_last4 ~ '^[0-9]{4}$'::text)),
    CONSTRAINT ck_statement_lines_description_not_pan CHECK ((NOT public.looks_like_pan(description))),
    CONSTRAINT ck_statement_lines_line_no_positive CHECK ((line_no >= 1))
);


ALTER TABLE public.statement_lines OWNER TO cardflow;

--
-- Name: COLUMN statement_lines.kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.statement_lines.kind IS 'Open set of statement line kinds (purchase, refund, fee, interest, installment, repayment, adjustment, info ...); no CHECK by design.';


--
-- Name: COLUMN statement_lines.amount_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.statement_lines.amount_minor IS 'Minor units; same convention as transactions.amount_minor (positive = liability increase, negative = credit). Informational lines may carry any sign.';


--
-- Name: COLUMN statement_lines.currency_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.statement_lines.currency_account_id IS 'Derived from statement_version_id by trigger; clients do not supply it.';


--
-- Name: statement_versions; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.statement_versions (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    statement_id uuid NOT NULL,
    version_no integer NOT NULL,
    source_kind text NOT NULL,
    source_document_id uuid,
    previous_balance_minor bigint,
    new_balance_minor bigint NOT NULL,
    min_due_minor bigint,
    payments_minor bigint,
    credits_minor bigint,
    fees_minor bigint,
    interest_minor bigint,
    installment_due_minor bigint,
    credit_balance_minor bigint,
    due_date date NOT NULL,
    recorded_by text NOT NULL,
    reason text,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    currency_account_id uuid NOT NULL,
    CONSTRAINT ck_statement_versions_reason_not_pan CHECK ((NOT public.looks_like_pan(reason))),
    CONSTRAINT ck_statement_versions_source_kind CHECK ((source_kind = ANY (ARRAY['pdf'::text, 'email'::text, 'screenshot'::text, 'csv'::text, 'manual'::text, 'correction'::text]))),
    CONSTRAINT ck_statement_versions_version_no_positive CHECK ((version_no >= 1))
);


ALTER TABLE public.statement_versions OWNER TO cardflow;

--
-- Name: COLUMN statement_versions.currency_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.statement_versions.currency_account_id IS 'Derived from statement_id by trigger; clients do not supply it.';


--
-- Name: statements; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.statements (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    statement_date date NOT NULL,
    due_date date NOT NULL,
    status text NOT NULL,
    current_version_id uuid,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_statements_due_after_statement CHECK ((due_date > statement_date)),
    CONSTRAINT ck_statements_status CHECK ((status = ANY (ARRAY['predicted'::text, 'issued'::text, 'amended'::text, 'partially_settled'::text, 'settled'::text, 'overdue'::text])))
);


ALTER TABLE public.statements OWNER TO cardflow;

--
-- Name: sync_changes; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.sync_changes (
    seq bigint NOT NULL,
    workspace_id uuid NOT NULL,
    table_name text NOT NULL,
    row_id uuid NOT NULL,
    op text NOT NULL,
    row_version bigint NOT NULL,
    payload jsonb,
    origin_device_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    txid xid8 DEFAULT pg_current_xact_id() NOT NULL,
    CONSTRAINT ck_sync_changes_op CHECK ((op = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);


ALTER TABLE public.sync_changes OWNER TO cardflow;

--
-- Name: COLUMN sync_changes.txid; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.sync_changes.txid IS 'Top-level transaction id of the writer. Pull with cursor (txid, seq) over rows whose txid < pg_snapshot_xmin(pg_current_snapshot()); seq alone is assigned at INSERT, not at COMMIT.';


--
-- Name: sync_changes_seq_seq; Type: SEQUENCE; Schema: public; Owner: cardflow
--

CREATE SEQUENCE public.sync_changes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_changes_seq_seq OWNER TO cardflow;

--
-- Name: sync_changes_seq_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: cardflow
--

ALTER SEQUENCE public.sync_changes_seq_seq OWNED BY public.sync_changes.seq;


--
-- Name: sync_conflicts; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.sync_conflicts (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    origin_device_id uuid,
    table_name text NOT NULL,
    row_id uuid NOT NULL,
    server_version bigint NOT NULL,
    client_base_version bigint NOT NULL,
    fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    server_payload jsonb NOT NULL,
    client_payload jsonb NOT NULL,
    status text NOT NULL,
    resolved_by text,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_sync_conflicts_status CHECK ((status = ANY (ARRAY['open'::text, 'resolved'::text])))
);


ALTER TABLE public.sync_conflicts OWNER TO cardflow;

--
-- Name: transaction_links; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.transaction_links (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    from_transaction_id uuid NOT NULL,
    to_transaction_id uuid NOT NULL,
    kind text NOT NULL,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    CONSTRAINT ck_transaction_links_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_transaction_links_distinct_transactions CHECK ((from_transaction_id <> to_transaction_id))
);


ALTER TABLE public.transaction_links OWNER TO cardflow;

--
-- Name: COLUMN transaction_links.kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.transaction_links.kind IS 'Open set (preauth_capture, refund_of, reversal_of, duplicate_of ...); no CHECK by design.';


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.transactions (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    currency_account_id uuid NOT NULL,
    card_id uuid,
    txn_type text NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    txn_at timestamp with time zone NOT NULL,
    txn_tz text NOT NULL,
    time_precision text NOT NULL,
    posted_on date,
    merchant text,
    mcc character(4),
    category text,
    status text NOT NULL,
    bank_reference text,
    parent_transaction_id uuid,
    fingerprint text NOT NULL,
    source_kind text NOT NULL,
    source_document_id uuid,
    confirmation_level text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    origin_device_id uuid,
    credit_account_id uuid NOT NULL,
    observed_at timestamp with time zone,
    CONSTRAINT ck_transactions_amount_nonzero CHECK ((amount_minor <> 0)),
    CONSTRAINT ck_transactions_amount_sign CHECK ((((txn_type = ANY (ARRAY['purchase'::text, 'cash_advance'::text, 'fee'::text, 'interest'::text, 'installment_principal'::text])) AND (amount_minor > 0)) OR ((txn_type = ANY (ARRAY['refund'::text, 'reversal'::text, 'repayment'::text])) AND (amount_minor < 0)) OR (txn_type = ANY (ARRAY['adjustment'::text, 'transfer'::text, 'preauth'::text])))),
    CONSTRAINT ck_transactions_category_not_pan CHECK ((NOT public.looks_like_pan(category))),
    CONSTRAINT ck_transactions_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_transactions_mcc_digits CHECK ((mcc ~ '^[0-9]{4}$'::text)),
    CONSTRAINT ck_transactions_merchant_not_pan CHECK ((NOT public.looks_like_pan(merchant))),
    CONSTRAINT ck_transactions_not_own_parent CHECK (((parent_transaction_id IS NULL) OR (parent_transaction_id <> id))),
    CONSTRAINT ck_transactions_status CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'reversed'::text]))),
    CONSTRAINT ck_transactions_time_precision CHECK ((time_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text]))),
    CONSTRAINT ck_transactions_txn_type CHECK ((txn_type = ANY (ARRAY['purchase'::text, 'refund'::text, 'reversal'::text, 'cash_advance'::text, 'fee'::text, 'interest'::text, 'repayment'::text, 'transfer'::text, 'preauth'::text, 'installment_principal'::text, 'adjustment'::text])))
);


ALTER TABLE public.transactions OWNER TO cardflow;

--
-- Name: COLUMN transactions.amount_minor; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.transactions.amount_minor IS 'Minor units of the currency account''s currency, never 0. Positive = liability increase (purchase, cash_advance, fee, interest, installment_principal); negative = credit (refund, reversal, repayment); adjustment, transfer, preauth: either sign.';


--
-- Name: COLUMN transactions.source_kind; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.transactions.source_kind IS 'Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, import ...); no CHECK by design.';


--
-- Name: COLUMN transactions.credit_account_id; Type: COMMENT; Schema: public; Owner: cardflow
--

COMMENT ON COLUMN public.transactions.credit_account_id IS 'Derived from currency_account_id by trigger; clients do not supply it.';


--
-- Name: users; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    email text,
    password_hash text,
    display_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    disabled_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_users_display_name_not_pan CHECK ((NOT public.looks_like_pan(display_name))),
    CONSTRAINT ck_users_email_lowercase CHECK ((email = lower(email))),
    CONSTRAINT ck_users_email_not_empty CHECK ((email <> ''::text)),
    CONSTRAINT ck_users_password_argon2id CHECK (((password_hash IS NULL) OR (password_hash ~~ '$argon2id$%'::text))),
    CONSTRAINT ck_users_password_needs_email CHECK (((password_hash IS NULL) OR (email IS NOT NULL)))
);


ALTER TABLE public.users OWNER TO cardflow;

--
-- Name: worker_heartbeats; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.worker_heartbeats (
    worker_id text NOT NULL,
    hostname text NOT NULL,
    pid integer NOT NULL,
    version text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    running_jobs integer DEFAULT 0 NOT NULL,
    CONSTRAINT ck_worker_heartbeats_running_jobs_non_negative CHECK ((running_jobs >= 0))
);


ALTER TABLE public.worker_heartbeats OWNER TO cardflow;

--
-- Name: workspace_members; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.workspace_members (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_workspace_members_role CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text])))
);


ALTER TABLE public.workspace_members OWNER TO cardflow;

--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_user_id uuid NOT NULL,
    kind text NOT NULL,
    dek_wrapped bytea,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_workspaces_id_not_nil CHECK ((id <> '00000000-0000-0000-0000-000000000000'::uuid)),
    CONSTRAINT ck_workspaces_kind CHECK ((kind = ANY (ARRAY['real'::text, 'demo'::text])))
);


ALTER TABLE public.workspaces OWNER TO cardflow;

--
-- Name: sync_changes seq; Type: DEFAULT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_changes ALTER COLUMN seq SET DEFAULT nextval('public.sync_changes_seq_seq'::regclass);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: billing_rule_versions ex_billing_rule_versions_scope_subject_period; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.billing_rule_versions
    ADD CONSTRAINT ex_billing_rule_versions_scope_subject_period EXCLUDE USING gist (COALESCE(workspace_id, '00000000-0000-0000-0000-000000000000'::uuid) WITH =, subject_id WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&) WHERE (((review_status = ANY (ARRAY['published'::text, 'user_declared'::text])) AND (deleted_at IS NULL)));


--
-- Name: rule_bindings ex_rule_bindings_account_period; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT ex_rule_bindings_account_period EXCLUDE USING gist (workspace_id WITH =, credit_account_id WITH =, COALESCE(currency_account_id, '00000000-0000-0000-0000-000000000000'::uuid) WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&) WHERE ((deleted_at IS NULL));


--
-- Name: audit_log pk_audit_log; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT pk_audit_log PRIMARY KEY (id);


--
-- Name: auth_sessions pk_auth_sessions; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT pk_auth_sessions PRIMARY KEY (id);


--
-- Name: banks pk_banks; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.banks
    ADD CONSTRAINT pk_banks PRIMARY KEY (id);


--
-- Name: billing_rule_versions pk_billing_rule_versions; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.billing_rule_versions
    ADD CONSTRAINT pk_billing_rule_versions PRIMARY KEY (id);


--
-- Name: card_products pk_card_products; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.card_products
    ADD CONSTRAINT pk_card_products PRIMARY KEY (id);


--
-- Name: cards pk_cards; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT pk_cards PRIMARY KEY (id);


--
-- Name: cash_accounts pk_cash_accounts; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_accounts
    ADD CONSTRAINT pk_cash_accounts PRIMARY KEY (id);


--
-- Name: cash_balance_snapshots pk_cash_balance_snapshots; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_balance_snapshots
    ADD CONSTRAINT pk_cash_balance_snapshots PRIMARY KEY (id);


--
-- Name: cash_events pk_cash_events; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT pk_cash_events PRIMARY KEY (id);


--
-- Name: cash_transfers pk_cash_transfers; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT pk_cash_transfers PRIMARY KEY (id);


--
-- Name: charges pk_charges; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT pk_charges PRIMARY KEY (id);


--
-- Name: consents pk_consents; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT pk_consents PRIMARY KEY (id);


--
-- Name: credit_accounts pk_credit_accounts; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_accounts
    ADD CONSTRAINT pk_credit_accounts PRIMARY KEY (id);


--
-- Name: credit_pool_members pk_credit_pool_members; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pool_members
    ADD CONSTRAINT pk_credit_pool_members PRIMARY KEY (id);


--
-- Name: credit_pools pk_credit_pools; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pools
    ADD CONSTRAINT pk_credit_pools PRIMARY KEY (id);


--
-- Name: currencies pk_currencies; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT pk_currencies PRIMARY KEY (code);


--
-- Name: currency_accounts pk_currency_accounts; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT pk_currency_accounts PRIMARY KEY (id);


--
-- Name: dedupe_keys pk_dedupe_keys; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.dedupe_keys
    ADD CONSTRAINT pk_dedupe_keys PRIMARY KEY (workspace_id, key_hash);


--
-- Name: deletion_tasks pk_deletion_tasks; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.deletion_tasks
    ADD CONSTRAINT pk_deletion_tasks PRIMARY KEY (id);


--
-- Name: devices pk_devices; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT pk_devices PRIMARY KEY (id);


--
-- Name: extraction_candidates pk_extraction_candidates; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.extraction_candidates
    ADD CONSTRAINT pk_extraction_candidates PRIMARY KEY (id);


--
-- Name: forecast_runs pk_forecast_runs; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.forecast_runs
    ADD CONSTRAINT pk_forecast_runs PRIMARY KEY (id);


--
-- Name: idempotency_keys pk_idempotency_keys; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT pk_idempotency_keys PRIMARY KEY (workspace_id, key);


--
-- Name: import_batch_items pk_import_batch_items; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batch_items
    ADD CONSTRAINT pk_import_batch_items PRIMARY KEY (id);


--
-- Name: import_batches pk_import_batches; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT pk_import_batches PRIMARY KEY (id);


--
-- Name: installment_plans pk_installment_plans; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_plans
    ADD CONSTRAINT pk_installment_plans PRIMARY KEY (id);


--
-- Name: installment_schedule pk_installment_schedule; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT pk_installment_schedule PRIMARY KEY (id);


--
-- Name: jobs pk_jobs; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT pk_jobs PRIMARY KEY (id);


--
-- Name: limit_adjustments pk_limit_adjustments; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_adjustments
    ADD CONSTRAINT pk_limit_adjustments PRIMARY KEY (id);


--
-- Name: limit_snapshots pk_limit_snapshots; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_snapshots
    ADD CONSTRAINT pk_limit_snapshots PRIMARY KEY (id);


--
-- Name: parse_jobs pk_parse_jobs; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.parse_jobs
    ADD CONSTRAINT pk_parse_jobs PRIMARY KEY (id);


--
-- Name: plan_allocations pk_plan_allocations; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT pk_plan_allocations PRIMARY KEY (id);


--
-- Name: plan_invalidations pk_plan_invalidations; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT pk_plan_invalidations PRIMARY KEY (id);


--
-- Name: plan_reservations pk_plan_reservations; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT pk_plan_reservations PRIMARY KEY (id);


--
-- Name: plan_run_checks pk_plan_run_checks; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_run_checks
    ADD CONSTRAINT pk_plan_run_checks PRIMARY KEY (id);


--
-- Name: plan_runs pk_plan_runs; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT pk_plan_runs PRIMARY KEY (id);


--
-- Name: plans pk_plans; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT pk_plans PRIMARY KEY (id);


--
-- Name: preauth_holds pk_preauth_holds; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT pk_preauth_holds PRIMARY KEY (id);


--
-- Name: reconciliation_items pk_reconciliation_items; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.reconciliation_items
    ADD CONSTRAINT pk_reconciliation_items PRIMARY KEY (id);


--
-- Name: recurring_items pk_recurring_items; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.recurring_items
    ADD CONSTRAINT pk_recurring_items PRIMARY KEY (id);


--
-- Name: repayment_allocation_totals pk_repayment_allocation_totals; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocation_totals
    ADD CONSTRAINT pk_repayment_allocation_totals PRIMARY KEY (repayment_id);


--
-- Name: repayment_allocations pk_repayment_allocations; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT pk_repayment_allocations PRIMARY KEY (id);


--
-- Name: repayments pk_repayments; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT pk_repayments PRIMARY KEY (id);


--
-- Name: rule_bindings pk_rule_bindings; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT pk_rule_bindings PRIMARY KEY (id);


--
-- Name: scenarios pk_scenarios; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.scenarios
    ADD CONSTRAINT pk_scenarios PRIMARY KEY (id);


--
-- Name: snapshot_included_events pk_snapshot_included_events; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT pk_snapshot_included_events PRIMARY KEY (id);


--
-- Name: source_documents pk_source_documents; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.source_documents
    ADD CONSTRAINT pk_source_documents PRIMARY KEY (id);


--
-- Name: statement_attributions pk_statement_attributions; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT pk_statement_attributions PRIMARY KEY (id);


--
-- Name: statement_lines pk_statement_lines; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT pk_statement_lines PRIMARY KEY (id);


--
-- Name: statement_versions pk_statement_versions; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT pk_statement_versions PRIMARY KEY (id);


--
-- Name: statements pk_statements; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT pk_statements PRIMARY KEY (id);


--
-- Name: sync_changes pk_sync_changes; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_changes
    ADD CONSTRAINT pk_sync_changes PRIMARY KEY (seq);


--
-- Name: sync_conflicts pk_sync_conflicts; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_conflicts
    ADD CONSTRAINT pk_sync_conflicts PRIMARY KEY (id);


--
-- Name: transaction_links pk_transaction_links; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT pk_transaction_links PRIMARY KEY (id);


--
-- Name: transactions pk_transactions; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT pk_transactions PRIMARY KEY (id);


--
-- Name: users pk_users; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users PRIMARY KEY (id);


--
-- Name: worker_heartbeats pk_worker_heartbeats; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.worker_heartbeats
    ADD CONSTRAINT pk_worker_heartbeats PRIMARY KEY (worker_id);


--
-- Name: workspace_members pk_workspace_members; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT pk_workspace_members PRIMARY KEY (id);


--
-- Name: workspaces pk_workspaces; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT pk_workspaces PRIMARY KEY (id);


--
-- Name: auth_sessions uq_auth_sessions_refresh_token_hash; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT uq_auth_sessions_refresh_token_hash UNIQUE (refresh_token_hash);


--
-- Name: auth_sessions uq_auth_sessions_rotated_from_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT uq_auth_sessions_rotated_from_id UNIQUE (rotated_from_id);


--
-- Name: auth_sessions uq_auth_sessions_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT uq_auth_sessions_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: banks uq_banks_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.banks
    ADD CONSTRAINT uq_banks_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: billing_rule_versions uq_billing_rule_versions_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.billing_rule_versions
    ADD CONSTRAINT uq_billing_rule_versions_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: card_products uq_card_products_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.card_products
    ADD CONSTRAINT uq_card_products_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: cards uq_cards_workspace_id_credit_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT uq_cards_workspace_id_credit_account_id_id UNIQUE (workspace_id, credit_account_id, id);


--
-- Name: cards uq_cards_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT uq_cards_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: cash_accounts uq_cash_accounts_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_accounts
    ADD CONSTRAINT uq_cash_accounts_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: cash_accounts uq_cash_accounts_workspace_id_id_currency; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_accounts
    ADD CONSTRAINT uq_cash_accounts_workspace_id_id_currency UNIQUE (workspace_id, id, currency);


--
-- Name: cash_balance_snapshots uq_cash_balance_snapshots_workspace_id_cash_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_balance_snapshots
    ADD CONSTRAINT uq_cash_balance_snapshots_workspace_id_cash_account_id_id UNIQUE (workspace_id, cash_account_id, id);


--
-- Name: cash_balance_snapshots uq_cash_balance_snapshots_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_balance_snapshots
    ADD CONSTRAINT uq_cash_balance_snapshots_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: cash_events uq_cash_events_workspace_id_cash_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT uq_cash_events_workspace_id_cash_account_id_id UNIQUE (workspace_id, cash_account_id, id);


--
-- Name: cash_events uq_cash_events_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT uq_cash_events_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: cash_transfers uq_cash_transfers_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT uq_cash_transfers_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: charges uq_charges_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT uq_charges_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: consents uq_consents_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT uq_consents_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: credit_accounts uq_credit_accounts_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_accounts
    ADD CONSTRAINT uq_credit_accounts_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: credit_pool_members uq_credit_pool_members_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pool_members
    ADD CONSTRAINT uq_credit_pool_members_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: credit_pools uq_credit_pools_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pools
    ADD CONSTRAINT uq_credit_pools_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: currency_accounts uq_currency_accounts_workspace_id_credit_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT uq_currency_accounts_workspace_id_credit_account_id_id UNIQUE (workspace_id, credit_account_id, id);


--
-- Name: currency_accounts uq_currency_accounts_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT uq_currency_accounts_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: currency_accounts uq_currency_accounts_workspace_id_id_currency; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT uq_currency_accounts_workspace_id_id_currency UNIQUE (workspace_id, id, currency);


--
-- Name: deletion_tasks uq_deletion_tasks_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.deletion_tasks
    ADD CONSTRAINT uq_deletion_tasks_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: devices uq_devices_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT uq_devices_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: extraction_candidates uq_extraction_candidates_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.extraction_candidates
    ADD CONSTRAINT uq_extraction_candidates_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: forecast_runs uq_forecast_runs_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.forecast_runs
    ADD CONSTRAINT uq_forecast_runs_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: import_batch_items uq_import_batch_items_import_batch_id_item_no; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batch_items
    ADD CONSTRAINT uq_import_batch_items_import_batch_id_item_no UNIQUE (import_batch_id, item_no);


--
-- Name: import_batch_items uq_import_batch_items_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batch_items
    ADD CONSTRAINT uq_import_batch_items_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: import_batches uq_import_batches_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT uq_import_batches_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: installment_plans uq_installment_plans_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_plans
    ADD CONSTRAINT uq_installment_plans_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: installment_schedule uq_installment_schedule_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT uq_installment_schedule_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: limit_adjustments uq_limit_adjustments_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_adjustments
    ADD CONSTRAINT uq_limit_adjustments_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: limit_snapshots uq_limit_snapshots_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_snapshots
    ADD CONSTRAINT uq_limit_snapshots_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: parse_jobs uq_parse_jobs_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.parse_jobs
    ADD CONSTRAINT uq_parse_jobs_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_allocations uq_plan_allocations_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT uq_plan_allocations_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_invalidations uq_plan_invalidations_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT uq_plan_invalidations_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_reservations uq_plan_reservations_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT uq_plan_reservations_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_run_checks uq_plan_run_checks_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_run_checks
    ADD CONSTRAINT uq_plan_run_checks_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_runs uq_plan_runs_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT uq_plan_runs_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plan_runs uq_plan_runs_workspace_id_id_currency; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT uq_plan_runs_workspace_id_id_currency UNIQUE (workspace_id, id, currency);


--
-- Name: plan_runs uq_plan_runs_workspace_id_plan_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT uq_plan_runs_workspace_id_plan_id_id UNIQUE (workspace_id, plan_id, id);


--
-- Name: plans uq_plans_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT uq_plans_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: plans uq_plans_workspace_id_id_currency; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT uq_plans_workspace_id_id_currency UNIQUE (workspace_id, id, currency);


--
-- Name: preauth_holds uq_preauth_holds_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT uq_preauth_holds_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: reconciliation_items uq_reconciliation_items_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.reconciliation_items
    ADD CONSTRAINT uq_reconciliation_items_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: recurring_items uq_recurring_items_workspace_id_cash_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.recurring_items
    ADD CONSTRAINT uq_recurring_items_workspace_id_cash_account_id_id UNIQUE (workspace_id, cash_account_id, id);


--
-- Name: recurring_items uq_recurring_items_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.recurring_items
    ADD CONSTRAINT uq_recurring_items_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: repayment_allocations uq_repayment_allocations_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT uq_repayment_allocations_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: repayments uq_repayments_workspace_id_cash_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT uq_repayments_workspace_id_cash_account_id_id UNIQUE (workspace_id, cash_account_id, id);


--
-- Name: repayments uq_repayments_workspace_id_currency_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT uq_repayments_workspace_id_currency_account_id_id UNIQUE (workspace_id, currency_account_id, id);


--
-- Name: repayments uq_repayments_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT uq_repayments_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: rule_bindings uq_rule_bindings_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT uq_rule_bindings_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: scenarios uq_scenarios_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.scenarios
    ADD CONSTRAINT uq_scenarios_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: snapshot_included_events uq_snapshot_included_events_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT uq_snapshot_included_events_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: source_documents uq_source_documents_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.source_documents
    ADD CONSTRAINT uq_source_documents_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: statement_attributions uq_statement_attributions_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT uq_statement_attributions_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: statement_lines uq_statement_lines_statement_version_id_line_no; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT uq_statement_lines_statement_version_id_line_no UNIQUE (statement_version_id, line_no);


--
-- Name: statement_lines uq_statement_lines_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT uq_statement_lines_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: statement_versions uq_statement_versions_statement_id_version_no; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT uq_statement_versions_statement_id_version_no UNIQUE (statement_id, version_no);


--
-- Name: statement_versions uq_statement_versions_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT uq_statement_versions_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: statement_versions uq_statement_versions_workspace_id_id_currency_account_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT uq_statement_versions_workspace_id_id_currency_account_id UNIQUE (workspace_id, id, currency_account_id);


--
-- Name: statement_versions uq_statement_versions_workspace_id_statement_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT uq_statement_versions_workspace_id_statement_id_id UNIQUE (workspace_id, statement_id, id);


--
-- Name: statements uq_statements_workspace_id_currency_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT uq_statements_workspace_id_currency_account_id_id UNIQUE (workspace_id, currency_account_id, id);


--
-- Name: statements uq_statements_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT uq_statements_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: sync_conflicts uq_sync_conflicts_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_conflicts
    ADD CONSTRAINT uq_sync_conflicts_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: transaction_links uq_transaction_links_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT uq_transaction_links_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: transactions uq_transactions_workspace_id_currency_account_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT uq_transactions_workspace_id_currency_account_id_id UNIQUE (workspace_id, currency_account_id, id);


--
-- Name: transactions uq_transactions_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT uq_transactions_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: users uq_users_email; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_email UNIQUE (email);


--
-- Name: workspace_members uq_workspace_members_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT uq_workspace_members_workspace_id_id UNIQUE (workspace_id, id);


--
-- Name: workspace_members uq_workspace_members_workspace_id_user_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT uq_workspace_members_workspace_id_user_id UNIQUE (workspace_id, user_id);


--
-- Name: ix_audit_log_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_audit_log_at ON public.audit_log USING btree (at);


--
-- Name: ix_audit_log_workspace_id_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_audit_log_workspace_id_at ON public.audit_log USING btree (workspace_id, at);


--
-- Name: ix_auth_sessions_device_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_auth_sessions_device_id ON public.auth_sessions USING btree (device_id);


--
-- Name: ix_billing_rule_versions_subject_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_billing_rule_versions_subject_id ON public.billing_rule_versions USING btree (subject_id);


--
-- Name: ix_card_products_bank_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_card_products_bank_id ON public.card_products USING btree (bank_id);


--
-- Name: ix_cards_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cards_credit_account_id ON public.cards USING btree (credit_account_id);


--
-- Name: ix_cards_replaced_by_card_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cards_replaced_by_card_id ON public.cards USING btree (replaced_by_card_id);


--
-- Name: ix_cash_balance_snapshots_cash_account_id_balance_as_of; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_balance_snapshots_cash_account_id_balance_as_of ON public.cash_balance_snapshots USING btree (cash_account_id, balance_as_of);


--
-- Name: ix_cash_events_cash_account_id_event_on; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_events_cash_account_id_event_on ON public.cash_events USING btree (cash_account_id, event_on) WHERE (deleted_at IS NULL);


--
-- Name: ix_cash_events_label_trgm; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_events_label_trgm ON public.cash_events USING gin (label public.gin_trgm_ops);


--
-- Name: ix_cash_events_linked_plan_run_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_events_linked_plan_run_id ON public.cash_events USING btree (linked_plan_run_id);


--
-- Name: ix_cash_events_linked_repayment_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_events_linked_repayment_id ON public.cash_events USING btree (linked_repayment_id);


--
-- Name: ix_cash_events_recurring_item_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_events_recurring_item_id ON public.cash_events USING btree (recurring_item_id);


--
-- Name: ix_cash_transfers_from_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_transfers_from_cash_account_id ON public.cash_transfers USING btree (from_cash_account_id);


--
-- Name: ix_cash_transfers_in_event_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_transfers_in_event_id ON public.cash_transfers USING btree (in_event_id);


--
-- Name: ix_cash_transfers_out_event_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_transfers_out_event_id ON public.cash_transfers USING btree (out_event_id);


--
-- Name: ix_cash_transfers_to_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_cash_transfers_to_cash_account_id ON public.cash_transfers USING btree (to_cash_account_id);


--
-- Name: ix_charges_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_charges_currency_account_id ON public.charges USING btree (currency_account_id);


--
-- Name: ix_charges_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_charges_statement_id ON public.charges USING btree (statement_id);


--
-- Name: ix_charges_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_charges_transaction_id ON public.charges USING btree (transaction_id);


--
-- Name: ix_consents_workspace_id_purpose; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_consents_workspace_id_purpose ON public.consents USING btree (workspace_id, purpose);


--
-- Name: ix_credit_accounts_bank_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_accounts_bank_id ON public.credit_accounts USING btree (bank_id);


--
-- Name: ix_credit_accounts_product_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_accounts_product_id ON public.credit_accounts USING btree (product_id);


--
-- Name: ix_credit_pool_members_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_pool_members_credit_account_id ON public.credit_pool_members USING btree (credit_account_id);


--
-- Name: ix_credit_pool_members_pool_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_pool_members_pool_id ON public.credit_pool_members USING btree (pool_id);


--
-- Name: ix_credit_pools_bank_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_pools_bank_id ON public.credit_pools USING btree (bank_id);


--
-- Name: ix_credit_pools_parent_pool_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_pools_parent_pool_id ON public.credit_pools USING btree (parent_pool_id);


--
-- Name: ix_deletion_tasks_status_grace_until; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_deletion_tasks_status_grace_until ON public.deletion_tasks USING btree (status, grace_until);


--
-- Name: ix_devices_user_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_devices_user_id ON public.devices USING btree (user_id);


--
-- Name: ix_extraction_candidates_parse_job_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_extraction_candidates_parse_job_id ON public.extraction_candidates USING btree (parse_job_id);


--
-- Name: ix_forecast_runs_scenario_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_forecast_runs_scenario_id ON public.forecast_runs USING btree (scenario_id);


--
-- Name: ix_idempotency_keys_created_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_idempotency_keys_created_at ON public.idempotency_keys USING btree (created_at);


--
-- Name: ix_import_batches_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_import_batches_source_document_id ON public.import_batches USING btree (source_document_id);


--
-- Name: ix_import_batches_target_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_import_batches_target_currency_account_id ON public.import_batches USING btree (target_currency_account_id);


--
-- Name: ix_installment_plans_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_installment_plans_transaction_id ON public.installment_plans USING btree (transaction_id);


--
-- Name: ix_installment_schedule_plan_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_installment_schedule_plan_id ON public.installment_schedule USING btree (plan_id);


--
-- Name: ix_jobs_queued_run_after_created_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_jobs_queued_run_after_created_at ON public.jobs USING btree (run_after, created_at) WHERE (status = 'queued'::text);


--
-- Name: ix_jobs_running_locked_until; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_jobs_running_locked_until ON public.jobs USING btree (locked_until) WHERE (status = 'running'::text);


--
-- Name: ix_limit_adjustments_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_adjustments_currency_account_id ON public.limit_adjustments USING btree (currency_account_id);


--
-- Name: ix_limit_adjustments_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_adjustments_source_document_id ON public.limit_adjustments USING btree (source_document_id);


--
-- Name: ix_limit_snapshots_currency_account_id_balance_as_of; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_snapshots_currency_account_id_balance_as_of ON public.limit_snapshots USING btree (currency_account_id, balance_as_of DESC);


--
-- Name: ix_limit_snapshots_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_snapshots_source_document_id ON public.limit_snapshots USING btree (source_document_id);


--
-- Name: ix_parse_jobs_import_batch_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_parse_jobs_import_batch_id ON public.parse_jobs USING btree (import_batch_id);


--
-- Name: ix_parse_jobs_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_parse_jobs_source_document_id ON public.parse_jobs USING btree (source_document_id);


--
-- Name: ix_plan_allocations_card_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_allocations_card_id ON public.plan_allocations USING btree (card_id);


--
-- Name: ix_plan_allocations_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_allocations_currency_account_id ON public.plan_allocations USING btree (currency_account_id);


--
-- Name: ix_plan_allocations_repay_from_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_allocations_repay_from_cash_account_id ON public.plan_allocations USING btree (repay_from_cash_account_id);


--
-- Name: ix_plan_allocations_run_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_allocations_run_id ON public.plan_allocations USING btree (run_id);


--
-- Name: ix_plan_invalidations_plan_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_invalidations_plan_id ON public.plan_invalidations USING btree (plan_id);


--
-- Name: ix_plan_invalidations_run_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_invalidations_run_id ON public.plan_invalidations USING btree (run_id);


--
-- Name: ix_plan_reservations_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_cash_account_id ON public.plan_reservations USING btree (cash_account_id);


--
-- Name: ix_plan_reservations_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_currency_account_id ON public.plan_reservations USING btree (currency_account_id);


--
-- Name: ix_plan_reservations_linked_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_linked_transaction_id ON public.plan_reservations USING btree (linked_transaction_id);


--
-- Name: ix_plan_reservations_plan_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_plan_id ON public.plan_reservations USING btree (plan_id);


--
-- Name: ix_plan_reservations_run_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_run_id ON public.plan_reservations USING btree (run_id);


--
-- Name: ix_plan_run_checks_run_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_run_checks_run_id ON public.plan_run_checks USING btree (run_id);


--
-- Name: ix_plan_run_checks_scenario_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_run_checks_scenario_id ON public.plan_run_checks USING btree (scenario_id);


--
-- Name: ix_plan_runs_decision_scenario_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_runs_decision_scenario_id ON public.plan_runs USING btree (decision_scenario_id);


--
-- Name: ix_plan_runs_plan_id_created_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_runs_plan_id_created_at ON public.plan_runs USING btree (plan_id, created_at);


--
-- Name: ix_preauth_holds_card_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_preauth_holds_card_id ON public.preauth_holds USING btree (card_id);


--
-- Name: ix_preauth_holds_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_preauth_holds_currency_account_id ON public.preauth_holds USING btree (currency_account_id);


--
-- Name: ix_preauth_holds_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_preauth_holds_source_document_id ON public.preauth_holds USING btree (source_document_id);


--
-- Name: ix_preauth_holds_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_preauth_holds_transaction_id ON public.preauth_holds USING btree (transaction_id);


--
-- Name: ix_reconciliation_items_workspace_id_status; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_reconciliation_items_workspace_id_status ON public.reconciliation_items USING btree (workspace_id, status);


--
-- Name: ix_recurring_items_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_recurring_items_cash_account_id ON public.recurring_items USING btree (cash_account_id);


--
-- Name: ix_repayment_allocations_repayment_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayment_allocations_repayment_id ON public.repayment_allocations USING btree (repayment_id);


--
-- Name: ix_repayment_allocations_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayment_allocations_statement_id ON public.repayment_allocations USING btree (statement_id);


--
-- Name: ix_repayments_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayments_cash_account_id ON public.repayments USING btree (cash_account_id);


--
-- Name: ix_repayments_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayments_currency_account_id ON public.repayments USING btree (currency_account_id);


--
-- Name: ix_repayments_evidence_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayments_evidence_document_id ON public.repayments USING btree (evidence_document_id);


--
-- Name: ix_rule_bindings_billing_rule_version_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_rule_bindings_billing_rule_version_id ON public.rule_bindings USING btree (billing_rule_version_id);


--
-- Name: ix_rule_bindings_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_rule_bindings_credit_account_id ON public.rule_bindings USING btree (credit_account_id);


--
-- Name: ix_rule_bindings_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_rule_bindings_currency_account_id ON public.rule_bindings USING btree (currency_account_id);


--
-- Name: ix_snapshot_included_events_cash_event_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_snapshot_included_events_cash_event_id ON public.snapshot_included_events USING btree (cash_event_id);


--
-- Name: ix_snapshot_included_events_snapshot_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_snapshot_included_events_snapshot_id ON public.snapshot_included_events USING btree (snapshot_id);


--
-- Name: ix_statement_attributions_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_attributions_statement_id ON public.statement_attributions USING btree (statement_id);


--
-- Name: ix_statement_attributions_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_attributions_transaction_id ON public.statement_attributions USING btree (transaction_id);


--
-- Name: ix_statement_lines_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_lines_transaction_id ON public.statement_lines USING btree (transaction_id);


--
-- Name: ix_statement_versions_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_versions_source_document_id ON public.statement_versions USING btree (source_document_id);


--
-- Name: ix_sync_changes_workspace_id_seq; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_sync_changes_workspace_id_seq ON public.sync_changes USING btree (workspace_id, seq);


--
-- Name: ix_sync_changes_workspace_id_txid_seq; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_sync_changes_workspace_id_txid_seq ON public.sync_changes USING btree (workspace_id, txid, seq);


--
-- Name: ix_sync_conflicts_workspace_id_table_name_row_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_sync_conflicts_workspace_id_table_name_row_id ON public.sync_conflicts USING btree (workspace_id, table_name, row_id);


--
-- Name: ix_transaction_links_from_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transaction_links_from_transaction_id ON public.transaction_links USING btree (from_transaction_id);


--
-- Name: ix_transaction_links_to_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transaction_links_to_transaction_id ON public.transaction_links USING btree (to_transaction_id);


--
-- Name: ix_transactions_card_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_card_id ON public.transactions USING btree (card_id);


--
-- Name: ix_transactions_currency_account_id_posted_on; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_currency_account_id_posted_on ON public.transactions USING btree (currency_account_id, posted_on);


--
-- Name: ix_transactions_merchant_trgm; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_merchant_trgm ON public.transactions USING gin (merchant public.gin_trgm_ops);


--
-- Name: ix_transactions_parent_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_parent_transaction_id ON public.transactions USING btree (parent_transaction_id);


--
-- Name: ix_transactions_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_source_document_id ON public.transactions USING btree (source_document_id);


--
-- Name: ix_transactions_workspace_id_fingerprint; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_workspace_id_fingerprint ON public.transactions USING btree (workspace_id, fingerprint);


--
-- Name: ix_worker_heartbeats_last_seen_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_worker_heartbeats_last_seen_at ON public.worker_heartbeats USING btree (last_seen_at);


--
-- Name: ix_workspace_members_user_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_workspace_members_user_id ON public.workspace_members USING btree (user_id);


--
-- Name: ix_workspaces_owner_user_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_workspaces_owner_user_id ON public.workspaces USING btree (owner_user_id);


--
-- Name: uq_credit_pool_members_pool_id_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_credit_pool_members_pool_id_credit_account_id ON public.credit_pool_members USING btree (pool_id, credit_account_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_currency_accounts_credit_account_id_currency; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_currency_accounts_credit_account_id_currency ON public.currency_accounts USING btree (credit_account_id, currency) WHERE (deleted_at IS NULL);


--
-- Name: uq_currency_accounts_one_primary; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_currency_accounts_one_primary ON public.currency_accounts USING btree (credit_account_id) WHERE (is_primary AND (deleted_at IS NULL));


--
-- Name: uq_installment_plans_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_installment_plans_transaction_id ON public.installment_plans USING btree (transaction_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_installment_schedule_plan_id_period_no; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_installment_schedule_plan_id_period_no ON public.installment_schedule USING btree (plan_id, period_no) WHERE (deleted_at IS NULL);


--
-- Name: uq_jobs_dedupe_key_active; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_jobs_dedupe_key_active ON public.jobs USING btree (dedupe_key) WHERE ((dedupe_key IS NOT NULL) AND (status = ANY (ARRAY['queued'::text, 'running'::text])));


--
-- Name: uq_plan_allocations_run_id_card_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_plan_allocations_run_id_card_id ON public.plan_allocations USING btree (run_id, card_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_plan_run_checks_run_id_scenario_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_plan_run_checks_run_id_scenario_id ON public.plan_run_checks USING btree (run_id, scenario_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_repayment_allocations_repayment_id_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_repayment_allocations_repayment_id_statement_id ON public.repayment_allocations USING btree (repayment_id, statement_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_snapshot_included_events_snapshot_id_cash_event_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_snapshot_included_events_snapshot_id_cash_event_id ON public.snapshot_included_events USING btree (snapshot_id, cash_event_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_source_documents_workspace_id_sha256; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_source_documents_workspace_id_sha256 ON public.source_documents USING btree (workspace_id, sha256) WHERE (deleted_at IS NULL);


--
-- Name: uq_statement_attributions_transaction_id_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_statement_attributions_transaction_id_statement_id ON public.statement_attributions USING btree (transaction_id, statement_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_statements_currency_account_id_statement_date; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_statements_currency_account_id_statement_date ON public.statements USING btree (currency_account_id, statement_date) WHERE (deleted_at IS NULL);


--
-- Name: uq_transaction_links_from_transaction_id_to_transaction_id_kind; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_transaction_links_from_transaction_id_to_transaction_id_kind ON public.transaction_links USING btree (from_transaction_id, to_transaction_id, kind) WHERE (deleted_at IS NULL);


--
-- Name: auth_sessions auth_sessions_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER auth_sessions_workspace_immutable BEFORE UPDATE OF workspace_id ON public.auth_sessions FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: banks banks_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER banks_row_version BEFORE UPDATE ON public.banks FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: banks banks_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER banks_workspace_immutable BEFORE UPDATE OF workspace_id ON public.banks FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: billing_rule_versions billing_rule_versions_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER billing_rule_versions_row_version BEFORE UPDATE ON public.billing_rule_versions FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: billing_rule_versions billing_rule_versions_subject_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER billing_rule_versions_subject_scope BEFORE INSERT OR UPDATE OF workspace_id, subject_kind, subject_id ON public.billing_rule_versions FOR EACH ROW EXECUTE FUNCTION public.check_rule_subject_scope();


--
-- Name: billing_rule_versions billing_rule_versions_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER billing_rule_versions_workspace_immutable BEFORE UPDATE OF workspace_id ON public.billing_rule_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: card_products card_products_bank_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER card_products_bank_scope BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON public.card_products FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('bank_id', 'banks');


--
-- Name: card_products card_products_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER card_products_row_version BEFORE UPDATE ON public.card_products FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: card_products card_products_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER card_products_workspace_immutable BEFORE UPDATE OF workspace_id ON public.card_products FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: cards cards_no_replacement_cycle; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cards_no_replacement_cycle BEFORE INSERT OR UPDATE OF replaced_by_card_id ON public.cards FOR EACH ROW EXECUTE FUNCTION public.check_card_replacement_cycle();


--
-- Name: cards cards_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cards_row_version BEFORE UPDATE ON public.cards FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: cards cards_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cards_workspace_immutable BEFORE UPDATE OF workspace_id ON public.cards FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: cash_accounts cash_accounts_currency_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_accounts_currency_immutable BEFORE UPDATE OF currency ON public.cash_accounts FOR EACH ROW EXECUTE FUNCTION public.forbid_column_update('currency');


--
-- Name: cash_accounts cash_accounts_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_accounts_row_version BEFORE UPDATE ON public.cash_accounts FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: cash_accounts cash_accounts_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_accounts_workspace_immutable BEFORE UPDATE OF workspace_id ON public.cash_accounts FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: cash_balance_snapshots cash_balance_snapshots_amounts_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_balance_snapshots_amounts_immutable BEFORE UPDATE ON public.cash_balance_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_column_update('cash_account_id', 'balance_minor', 'balance_as_of', 'observed_at', 'recorded_at');


--
-- Name: cash_balance_snapshots cash_balance_snapshots_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_balance_snapshots_no_delete BEFORE DELETE ON public.cash_balance_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: cash_balance_snapshots cash_balance_snapshots_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_balance_snapshots_no_truncate BEFORE TRUNCATE ON public.cash_balance_snapshots FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: cash_balance_snapshots cash_balance_snapshots_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_balance_snapshots_row_version BEFORE UPDATE ON public.cash_balance_snapshots FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: cash_balance_snapshots cash_balance_snapshots_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_balance_snapshots_workspace_immutable BEFORE UPDATE OF workspace_id ON public.cash_balance_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: cash_events cash_events_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_events_row_version BEFORE UPDATE ON public.cash_events FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: cash_events cash_events_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_events_workspace_immutable BEFORE UPDATE OF workspace_id ON public.cash_events FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: cash_transfers cash_transfers_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_transfers_row_version BEFORE UPDATE ON public.cash_transfers FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: cash_transfers cash_transfers_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER cash_transfers_workspace_immutable BEFORE UPDATE OF workspace_id ON public.cash_transfers FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: charges charges_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER charges_row_version BEFORE UPDATE ON public.charges FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: charges charges_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER charges_workspace_immutable BEFORE UPDATE OF workspace_id ON public.charges FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: consents consents_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER consents_row_version BEFORE UPDATE ON public.consents FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: consents consents_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER consents_workspace_immutable BEFORE UPDATE OF workspace_id ON public.consents FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: credit_accounts credit_accounts_bank_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_bank_scope BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('bank_id', 'banks');


--
-- Name: credit_accounts credit_accounts_product_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_product_scope BEFORE INSERT OR UPDATE OF workspace_id, product_id ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('product_id', 'card_products');


--
-- Name: credit_accounts credit_accounts_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_row_version BEFORE UPDATE ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: credit_accounts credit_accounts_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_workspace_immutable BEFORE UPDATE OF workspace_id ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: credit_pool_members credit_pool_members_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pool_members_row_version BEFORE UPDATE ON public.credit_pool_members FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: credit_pool_members credit_pool_members_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pool_members_workspace_immutable BEFORE UPDATE OF workspace_id ON public.credit_pool_members FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: credit_pools credit_pools_bank_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pools_bank_scope BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('bank_id', 'banks');


--
-- Name: credit_pools credit_pools_no_cycle; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pools_no_cycle BEFORE INSERT OR UPDATE OF parent_pool_id ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.check_credit_pool_cycle();


--
-- Name: credit_pools credit_pools_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pools_row_version BEFORE UPDATE ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: credit_pools credit_pools_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pools_workspace_immutable BEFORE UPDATE OF workspace_id ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: currency_accounts currency_accounts_identity_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER currency_accounts_identity_immutable BEFORE UPDATE OF credit_account_id, currency ON public.currency_accounts FOR EACH ROW EXECUTE FUNCTION public.forbid_column_update('credit_account_id', 'currency');


--
-- Name: currency_accounts currency_accounts_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER currency_accounts_row_version BEFORE UPDATE ON public.currency_accounts FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: currency_accounts currency_accounts_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER currency_accounts_workspace_immutable BEFORE UPDATE OF workspace_id ON public.currency_accounts FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: dedupe_keys dedupe_keys_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER dedupe_keys_workspace_immutable BEFORE UPDATE OF workspace_id ON public.dedupe_keys FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: deletion_tasks deletion_tasks_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER deletion_tasks_workspace_immutable BEFORE UPDATE OF workspace_id ON public.deletion_tasks FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: devices devices_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER devices_workspace_immutable BEFORE UPDATE OF workspace_id ON public.devices FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: extraction_candidates extraction_candidates_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER extraction_candidates_workspace_immutable BEFORE UPDATE OF workspace_id ON public.extraction_candidates FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: forecast_runs forecast_runs_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER forecast_runs_row_version BEFORE UPDATE ON public.forecast_runs FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: forecast_runs forecast_runs_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER forecast_runs_workspace_immutable BEFORE UPDATE OF workspace_id ON public.forecast_runs FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: idempotency_keys idempotency_keys_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER idempotency_keys_workspace_immutable BEFORE UPDATE OF workspace_id ON public.idempotency_keys FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: import_batch_items import_batch_items_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER import_batch_items_workspace_immutable BEFORE UPDATE OF workspace_id ON public.import_batch_items FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: import_batches import_batches_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER import_batches_workspace_immutable BEFORE UPDATE OF workspace_id ON public.import_batches FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: installment_plans installment_plans_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER installment_plans_row_version BEFORE UPDATE ON public.installment_plans FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: installment_plans installment_plans_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER installment_plans_workspace_immutable BEFORE UPDATE OF workspace_id ON public.installment_plans FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: installment_schedule installment_schedule_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER installment_schedule_row_version BEFORE UPDATE ON public.installment_schedule FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: installment_schedule installment_schedule_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER installment_schedule_workspace_immutable BEFORE UPDATE OF workspace_id ON public.installment_schedule FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: limit_adjustments limit_adjustments_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_adjustments_row_version BEFORE UPDATE ON public.limit_adjustments FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: limit_adjustments limit_adjustments_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_adjustments_workspace_immutable BEFORE UPDATE OF workspace_id ON public.limit_adjustments FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: limit_snapshots limit_snapshots_amounts_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_snapshots_amounts_immutable BEFORE UPDATE ON public.limit_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_column_update('currency_account_id', 'fixed_minor', 'temp_minor', 'temp_expires_on', 'special_minor', 'used_minor', 'available_raw_minor', 'includes_holds', 'balance_as_of', 'observed_at', 'recorded_at');


--
-- Name: limit_snapshots limit_snapshots_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_snapshots_no_delete BEFORE DELETE ON public.limit_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: limit_snapshots limit_snapshots_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_snapshots_no_truncate BEFORE TRUNCATE ON public.limit_snapshots FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: limit_snapshots limit_snapshots_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_snapshots_row_version BEFORE UPDATE ON public.limit_snapshots FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: limit_snapshots limit_snapshots_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER limit_snapshots_workspace_immutable BEFORE UPDATE OF workspace_id ON public.limit_snapshots FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: parse_jobs parse_jobs_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER parse_jobs_workspace_immutable BEFORE UPDATE OF workspace_id ON public.parse_jobs FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plan_allocations plan_allocations_derive_credit_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_derive_credit_account BEFORE INSERT OR UPDATE OF currency_account_id, credit_account_id ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('credit_account_id', 'currency_accounts', 'currency_account_id', 'credit_account_id');


--
-- Name: plan_allocations plan_allocations_derive_currency; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_derive_currency BEFORE INSERT OR UPDATE OF run_id, currency ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency', 'plan_runs', 'run_id', 'currency');


--
-- Name: plan_allocations plan_allocations_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_immutable BEFORE UPDATE ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite();


--
-- Name: plan_allocations plan_allocations_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_no_delete BEFORE DELETE ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_allocations plan_allocations_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_no_truncate BEFORE TRUNCATE ON public.plan_allocations FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_allocations plan_allocations_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_row_version BEFORE UPDATE ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plan_allocations plan_allocations_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_allocations_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plan_allocations FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plan_invalidations plan_invalidations_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_invalidations_row_version BEFORE UPDATE ON public.plan_invalidations FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plan_invalidations plan_invalidations_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_invalidations_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plan_invalidations FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plan_reservations plan_reservations_derive_currency; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_reservations_derive_currency BEFORE INSERT OR UPDATE OF plan_id, currency ON public.plan_reservations FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency', 'plans', 'plan_id', 'currency');


--
-- Name: plan_reservations plan_reservations_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_reservations_row_version BEFORE UPDATE ON public.plan_reservations FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plan_reservations plan_reservations_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_reservations_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plan_reservations FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plan_run_checks plan_run_checks_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_run_checks_immutable BEFORE UPDATE ON public.plan_run_checks FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite();


--
-- Name: plan_run_checks plan_run_checks_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_run_checks_no_delete BEFORE DELETE ON public.plan_run_checks FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_run_checks plan_run_checks_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_run_checks_no_truncate BEFORE TRUNCATE ON public.plan_run_checks FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_run_checks plan_run_checks_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_run_checks_row_version BEFORE UPDATE ON public.plan_run_checks FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plan_run_checks plan_run_checks_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_run_checks_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plan_run_checks FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plan_runs plan_runs_derive_currency; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_derive_currency BEFORE INSERT OR UPDATE OF plan_id, currency ON public.plan_runs FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency', 'plans', 'plan_id', 'currency');


--
-- Name: plan_runs plan_runs_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_immutable BEFORE UPDATE ON public.plan_runs FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite();


--
-- Name: plan_runs plan_runs_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_no_delete BEFORE DELETE ON public.plan_runs FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_runs plan_runs_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_no_truncate BEFORE TRUNCATE ON public.plan_runs FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: plan_runs plan_runs_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_row_version BEFORE UPDATE ON public.plan_runs FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plan_runs plan_runs_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plan_runs_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plan_runs FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: plans plans_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plans_row_version BEFORE UPDATE ON public.plans FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: plans plans_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER plans_workspace_immutable BEFORE UPDATE OF workspace_id ON public.plans FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: preauth_holds preauth_holds_derive_credit_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER preauth_holds_derive_credit_account BEFORE INSERT OR UPDATE OF currency_account_id, credit_account_id ON public.preauth_holds FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('credit_account_id', 'currency_accounts', 'currency_account_id', 'credit_account_id');


--
-- Name: preauth_holds preauth_holds_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER preauth_holds_row_version BEFORE UPDATE ON public.preauth_holds FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: preauth_holds preauth_holds_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER preauth_holds_workspace_immutable BEFORE UPDATE OF workspace_id ON public.preauth_holds FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: reconciliation_items reconciliation_items_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER reconciliation_items_row_version BEFORE UPDATE ON public.reconciliation_items FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: reconciliation_items reconciliation_items_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER reconciliation_items_workspace_immutable BEFORE UPDATE OF workspace_id ON public.reconciliation_items FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: recurring_items recurring_items_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER recurring_items_row_version BEFORE UPDATE ON public.recurring_items FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: recurring_items recurring_items_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER recurring_items_workspace_immutable BEFORE UPDATE OF workspace_id ON public.recurring_items FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: repayment_allocation_totals repayment_allocation_totals_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayment_allocation_totals_workspace_immutable BEFORE UPDATE OF workspace_id ON public.repayment_allocation_totals FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: repayment_allocations repayment_allocations_derive_currency_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayment_allocations_derive_currency_account BEFORE INSERT OR UPDATE OF repayment_id, currency_account_id ON public.repayment_allocations FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency_account_id', 'repayments', 'repayment_id', 'currency_account_id');


--
-- Name: repayment_allocations repayment_allocations_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayment_allocations_row_version BEFORE UPDATE ON public.repayment_allocations FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: repayment_allocations repayment_allocations_totals; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayment_allocations_totals AFTER INSERT OR DELETE OR UPDATE OF repayment_id, amount_minor, deleted_at ON public.repayment_allocations FOR EACH ROW EXECUTE FUNCTION public.maintain_repayment_allocation_totals();


--
-- Name: repayment_allocations repayment_allocations_within_amount; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE CONSTRAINT TRIGGER repayment_allocations_within_amount AFTER INSERT OR UPDATE ON public.repayment_allocations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.repayment_allocations_check();


--
-- Name: repayment_allocations repayment_allocations_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayment_allocations_workspace_immutable BEFORE UPDATE OF workspace_id ON public.repayment_allocations FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: repayments repayments_allocations_within_amount; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE CONSTRAINT TRIGGER repayments_allocations_within_amount AFTER UPDATE OF amount_minor, status, deleted_at ON public.repayments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.repayments_allocation_check();


--
-- Name: repayments repayments_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayments_row_version BEFORE UPDATE ON public.repayments FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: repayments repayments_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER repayments_workspace_immutable BEFORE UPDATE OF workspace_id ON public.repayments FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: rule_bindings rule_bindings_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER rule_bindings_row_version BEFORE UPDATE ON public.rule_bindings FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: rule_bindings rule_bindings_rule_version_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER rule_bindings_rule_version_scope BEFORE INSERT OR UPDATE OF workspace_id, billing_rule_version_id ON public.rule_bindings FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('billing_rule_version_id', 'billing_rule_versions');


--
-- Name: rule_bindings rule_bindings_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER rule_bindings_workspace_immutable BEFORE UPDATE OF workspace_id ON public.rule_bindings FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: scenarios scenarios_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER scenarios_row_version BEFORE UPDATE ON public.scenarios FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: scenarios scenarios_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER scenarios_workspace_immutable BEFORE UPDATE OF workspace_id ON public.scenarios FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: snapshot_included_events snapshot_included_events_derive_cash_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER snapshot_included_events_derive_cash_account BEFORE INSERT OR UPDATE OF snapshot_id, cash_account_id ON public.snapshot_included_events FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('cash_account_id', 'cash_balance_snapshots', 'snapshot_id', 'cash_account_id');


--
-- Name: snapshot_included_events snapshot_included_events_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER snapshot_included_events_row_version BEFORE UPDATE ON public.snapshot_included_events FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: snapshot_included_events snapshot_included_events_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER snapshot_included_events_workspace_immutable BEFORE UPDATE OF workspace_id ON public.snapshot_included_events FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: source_documents source_documents_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER source_documents_row_version BEFORE UPDATE ON public.source_documents FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: source_documents source_documents_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER source_documents_workspace_immutable BEFORE UPDATE OF workspace_id ON public.source_documents FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: statement_attributions statement_attributions_derive_currency_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_attributions_derive_currency_account BEFORE INSERT OR UPDATE OF transaction_id, currency_account_id ON public.statement_attributions FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency_account_id', 'transactions', 'transaction_id', 'currency_account_id');


--
-- Name: statement_attributions statement_attributions_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_attributions_row_version BEFORE UPDATE ON public.statement_attributions FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: statement_attributions statement_attributions_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_attributions_workspace_immutable BEFORE UPDATE OF workspace_id ON public.statement_attributions FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: statement_lines statement_lines_derive_currency_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_derive_currency_account BEFORE INSERT OR UPDATE OF statement_version_id, currency_account_id ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency_account_id', 'statement_versions', 'statement_version_id', 'currency_account_id');


--
-- Name: statement_lines statement_lines_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_immutable BEFORE UPDATE ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite();


--
-- Name: statement_lines statement_lines_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_no_delete BEFORE DELETE ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: statement_lines statement_lines_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_no_truncate BEFORE TRUNCATE ON public.statement_lines FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: statement_lines statement_lines_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_row_version BEFORE UPDATE ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: statement_lines statement_lines_same_transaction; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_same_transaction BEFORE INSERT ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.check_statement_line_transaction();


--
-- Name: statement_lines statement_lines_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_lines_workspace_immutable BEFORE UPDATE OF workspace_id ON public.statement_lines FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: statement_versions statement_versions_derive_currency_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_derive_currency_account BEFORE INSERT OR UPDATE OF statement_id, currency_account_id ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('currency_account_id', 'statements', 'statement_id', 'currency_account_id');


--
-- Name: statement_versions statement_versions_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_immutable BEFORE UPDATE ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite();


--
-- Name: statement_versions statement_versions_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_no_delete BEFORE DELETE ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: statement_versions statement_versions_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_no_truncate BEFORE TRUNCATE ON public.statement_versions FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete();


--
-- Name: statement_versions statement_versions_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_row_version BEFORE UPDATE ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: statement_versions statement_versions_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_workspace_immutable BEFORE UPDATE OF workspace_id ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: statements statements_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statements_row_version BEFORE UPDATE ON public.statements FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: statements statements_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statements_workspace_immutable BEFORE UPDATE OF workspace_id ON public.statements FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: sync_changes sync_changes_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER sync_changes_workspace_immutable BEFORE UPDATE OF workspace_id ON public.sync_changes FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: sync_conflicts sync_conflicts_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER sync_conflicts_workspace_immutable BEFORE UPDATE OF workspace_id ON public.sync_conflicts FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: transaction_links transaction_links_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER transaction_links_row_version BEFORE UPDATE ON public.transaction_links FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: transaction_links transaction_links_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER transaction_links_workspace_immutable BEFORE UPDATE OF workspace_id ON public.transaction_links FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: transactions transactions_derive_credit_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER transactions_derive_credit_account BEFORE INSERT OR UPDATE OF currency_account_id, credit_account_id ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent('credit_account_id', 'currency_accounts', 'currency_account_id', 'credit_account_id');


--
-- Name: transactions transactions_row_version; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER transactions_row_version BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: transactions transactions_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER transactions_workspace_immutable BEFORE UPDATE OF workspace_id ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: workspace_members workspace_members_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER workspace_members_workspace_immutable BEFORE UPDATE OF workspace_id ON public.workspace_members FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: auth_sessions fk_auth_sessions_device_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT fk_auth_sessions_device_id FOREIGN KEY (workspace_id, device_id) REFERENCES public.devices(workspace_id, id);


--
-- Name: auth_sessions fk_auth_sessions_rotated_from_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT fk_auth_sessions_rotated_from_id FOREIGN KEY (workspace_id, rotated_from_id) REFERENCES public.auth_sessions(workspace_id, id);


--
-- Name: banks fk_banks_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.banks
    ADD CONSTRAINT fk_banks_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: billing_rule_versions fk_billing_rule_versions_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.billing_rule_versions
    ADD CONSTRAINT fk_billing_rule_versions_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: card_products fk_card_products_bank_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.card_products
    ADD CONSTRAINT fk_card_products_bank_id FOREIGN KEY (bank_id) REFERENCES public.banks(id);


--
-- Name: card_products fk_card_products_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.card_products
    ADD CONSTRAINT fk_card_products_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: cards fk_cards_credit_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT fk_cards_credit_account_id FOREIGN KEY (workspace_id, credit_account_id) REFERENCES public.credit_accounts(workspace_id, id);


--
-- Name: cards fk_cards_replaced_by_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT fk_cards_replaced_by_card_id FOREIGN KEY (workspace_id, replaced_by_card_id) REFERENCES public.cards(workspace_id, id);


--
-- Name: cash_accounts fk_cash_accounts_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_accounts
    ADD CONSTRAINT fk_cash_accounts_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: cash_accounts fk_cash_accounts_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_accounts
    ADD CONSTRAINT fk_cash_accounts_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: cash_balance_snapshots fk_cash_balance_snapshots_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_balance_snapshots
    ADD CONSTRAINT fk_cash_balance_snapshots_cash_account_id FOREIGN KEY (workspace_id, cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: cash_events fk_cash_events_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_cash_account_id FOREIGN KEY (workspace_id, cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: cash_events fk_cash_events_cash_account_id_linked_repayment_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_cash_account_id_linked_repayment_id FOREIGN KEY (workspace_id, cash_account_id, linked_repayment_id) REFERENCES public.repayments(workspace_id, cash_account_id, id);


--
-- Name: cash_events fk_cash_events_cash_account_id_recurring_item_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_cash_account_id_recurring_item_id FOREIGN KEY (workspace_id, cash_account_id, recurring_item_id) REFERENCES public.recurring_items(workspace_id, cash_account_id, id);


--
-- Name: cash_events fk_cash_events_linked_plan_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_linked_plan_run_id FOREIGN KEY (workspace_id, linked_plan_run_id) REFERENCES public.plan_runs(workspace_id, id);


--
-- Name: cash_transfers fk_cash_transfers_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: cash_transfers fk_cash_transfers_from_cash_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_from_cash_account_id_currency FOREIGN KEY (workspace_id, from_cash_account_id, currency) REFERENCES public.cash_accounts(workspace_id, id, currency);


--
-- Name: cash_transfers fk_cash_transfers_from_cash_account_id_out_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_from_cash_account_id_out_event_id FOREIGN KEY (workspace_id, from_cash_account_id, out_event_id) REFERENCES public.cash_events(workspace_id, cash_account_id, id);


--
-- Name: cash_transfers fk_cash_transfers_to_cash_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_to_cash_account_id_currency FOREIGN KEY (workspace_id, to_cash_account_id, currency) REFERENCES public.cash_accounts(workspace_id, id, currency);


--
-- Name: cash_transfers fk_cash_transfers_to_cash_account_id_in_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_to_cash_account_id_in_event_id FOREIGN KEY (workspace_id, to_cash_account_id, in_event_id) REFERENCES public.cash_events(workspace_id, cash_account_id, id);


--
-- Name: charges fk_charges_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: charges fk_charges_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: charges fk_charges_currency_account_id_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency_account_id_statement_id FOREIGN KEY (workspace_id, currency_account_id, statement_id) REFERENCES public.statements(workspace_id, currency_account_id, id);


--
-- Name: charges fk_charges_currency_account_id_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency_account_id_transaction_id FOREIGN KEY (workspace_id, currency_account_id, transaction_id) REFERENCES public.transactions(workspace_id, currency_account_id, id);


--
-- Name: consents fk_consents_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_consents_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: credit_accounts fk_credit_accounts_bank_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_accounts
    ADD CONSTRAINT fk_credit_accounts_bank_id FOREIGN KEY (bank_id) REFERENCES public.banks(id);


--
-- Name: credit_accounts fk_credit_accounts_product_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_accounts
    ADD CONSTRAINT fk_credit_accounts_product_id FOREIGN KEY (product_id) REFERENCES public.card_products(id);


--
-- Name: credit_accounts fk_credit_accounts_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_accounts
    ADD CONSTRAINT fk_credit_accounts_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: credit_pool_members fk_credit_pool_members_credit_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pool_members
    ADD CONSTRAINT fk_credit_pool_members_credit_account_id FOREIGN KEY (workspace_id, credit_account_id) REFERENCES public.credit_accounts(workspace_id, id);


--
-- Name: credit_pool_members fk_credit_pool_members_pool_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pool_members
    ADD CONSTRAINT fk_credit_pool_members_pool_id FOREIGN KEY (workspace_id, pool_id) REFERENCES public.credit_pools(workspace_id, id);


--
-- Name: credit_pools fk_credit_pools_bank_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pools
    ADD CONSTRAINT fk_credit_pools_bank_id FOREIGN KEY (bank_id) REFERENCES public.banks(id);


--
-- Name: credit_pools fk_credit_pools_parent_pool_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pools
    ADD CONSTRAINT fk_credit_pools_parent_pool_id FOREIGN KEY (workspace_id, parent_pool_id) REFERENCES public.credit_pools(workspace_id, id);


--
-- Name: credit_pools fk_credit_pools_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pools
    ADD CONSTRAINT fk_credit_pools_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: currency_accounts fk_currency_accounts_credit_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT fk_currency_accounts_credit_account_id FOREIGN KEY (workspace_id, credit_account_id) REFERENCES public.credit_accounts(workspace_id, id);


--
-- Name: currency_accounts fk_currency_accounts_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT fk_currency_accounts_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: dedupe_keys fk_dedupe_keys_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.dedupe_keys
    ADD CONSTRAINT fk_dedupe_keys_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: devices fk_devices_user_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_devices_user_id FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: devices fk_devices_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_devices_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: extraction_candidates fk_extraction_candidates_parse_job_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.extraction_candidates
    ADD CONSTRAINT fk_extraction_candidates_parse_job_id FOREIGN KEY (workspace_id, parse_job_id) REFERENCES public.parse_jobs(workspace_id, id);


--
-- Name: forecast_runs fk_forecast_runs_scenario_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.forecast_runs
    ADD CONSTRAINT fk_forecast_runs_scenario_id FOREIGN KEY (workspace_id, scenario_id) REFERENCES public.scenarios(workspace_id, id);


--
-- Name: idempotency_keys fk_idempotency_keys_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_idempotency_keys_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: import_batch_items fk_import_batch_items_import_batch_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batch_items
    ADD CONSTRAINT fk_import_batch_items_import_batch_id FOREIGN KEY (workspace_id, import_batch_id) REFERENCES public.import_batches(workspace_id, id);


--
-- Name: import_batches fk_import_batches_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: import_batches fk_import_batches_target_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_target_currency_account_id FOREIGN KEY (workspace_id, target_currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: import_batches fk_import_batches_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: installment_plans fk_installment_plans_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_plans
    ADD CONSTRAINT fk_installment_plans_transaction_id FOREIGN KEY (workspace_id, transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: installment_schedule fk_installment_schedule_plan_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT fk_installment_schedule_plan_id FOREIGN KEY (workspace_id, plan_id) REFERENCES public.installment_plans(workspace_id, id);


--
-- Name: limit_adjustments fk_limit_adjustments_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_adjustments
    ADD CONSTRAINT fk_limit_adjustments_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: limit_adjustments fk_limit_adjustments_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_adjustments
    ADD CONSTRAINT fk_limit_adjustments_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: limit_snapshots fk_limit_snapshots_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_snapshots
    ADD CONSTRAINT fk_limit_snapshots_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: limit_snapshots fk_limit_snapshots_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_snapshots
    ADD CONSTRAINT fk_limit_snapshots_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: parse_jobs fk_parse_jobs_import_batch_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.parse_jobs
    ADD CONSTRAINT fk_parse_jobs_import_batch_id FOREIGN KEY (workspace_id, import_batch_id) REFERENCES public.import_batches(workspace_id, id);


--
-- Name: parse_jobs fk_parse_jobs_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.parse_jobs
    ADD CONSTRAINT fk_parse_jobs_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: plan_allocations fk_plan_allocations_credit_account_id_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_credit_account_id_card_id FOREIGN KEY (workspace_id, credit_account_id, card_id) REFERENCES public.cards(workspace_id, credit_account_id, id);


--
-- Name: plan_allocations fk_plan_allocations_credit_account_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_credit_account_id_currency_account_id FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, credit_account_id, id);


--
-- Name: plan_allocations fk_plan_allocations_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: plan_allocations fk_plan_allocations_repay_from_cash_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_repay_from_cash_account_id_currency FOREIGN KEY (workspace_id, repay_from_cash_account_id, currency) REFERENCES public.cash_accounts(workspace_id, id, currency);


--
-- Name: plan_allocations fk_plan_allocations_run_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_run_id_currency FOREIGN KEY (workspace_id, run_id, currency) REFERENCES public.plan_runs(workspace_id, id, currency);


--
-- Name: plan_invalidations fk_plan_invalidations_plan_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT fk_plan_invalidations_plan_id FOREIGN KEY (workspace_id, plan_id) REFERENCES public.plans(workspace_id, id);


--
-- Name: plan_invalidations fk_plan_invalidations_plan_id_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT fk_plan_invalidations_plan_id_run_id FOREIGN KEY (workspace_id, plan_id, run_id) REFERENCES public.plan_runs(workspace_id, plan_id, id);


--
-- Name: plan_reservations fk_plan_reservations_cash_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_cash_account_id_currency FOREIGN KEY (workspace_id, cash_account_id, currency) REFERENCES public.cash_accounts(workspace_id, id, currency);


--
-- Name: plan_reservations fk_plan_reservations_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: plan_reservations fk_plan_reservations_currency_account_id_linked_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_currency_account_id_linked_transaction_id FOREIGN KEY (workspace_id, currency_account_id, linked_transaction_id) REFERENCES public.transactions(workspace_id, currency_account_id, id);


--
-- Name: plan_reservations fk_plan_reservations_plan_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_plan_id_currency FOREIGN KEY (workspace_id, plan_id, currency) REFERENCES public.plans(workspace_id, id, currency);


--
-- Name: plan_reservations fk_plan_reservations_plan_id_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_plan_id_run_id FOREIGN KEY (workspace_id, plan_id, run_id) REFERENCES public.plan_runs(workspace_id, plan_id, id);


--
-- Name: plan_run_checks fk_plan_run_checks_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_run_checks
    ADD CONSTRAINT fk_plan_run_checks_run_id FOREIGN KEY (workspace_id, run_id) REFERENCES public.plan_runs(workspace_id, id);


--
-- Name: plan_run_checks fk_plan_run_checks_scenario_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_run_checks
    ADD CONSTRAINT fk_plan_run_checks_scenario_id FOREIGN KEY (workspace_id, scenario_id) REFERENCES public.scenarios(workspace_id, id);


--
-- Name: plan_runs fk_plan_runs_decision_scenario_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT fk_plan_runs_decision_scenario_id FOREIGN KEY (workspace_id, decision_scenario_id) REFERENCES public.scenarios(workspace_id, id);


--
-- Name: plan_runs fk_plan_runs_plan_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT fk_plan_runs_plan_id_currency FOREIGN KEY (workspace_id, plan_id, currency) REFERENCES public.plans(workspace_id, id, currency);


--
-- Name: plans fk_plans_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT fk_plans_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: plans fk_plans_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT fk_plans_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: preauth_holds fk_preauth_holds_credit_account_id_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_credit_account_id_card_id FOREIGN KEY (workspace_id, credit_account_id, card_id) REFERENCES public.cards(workspace_id, credit_account_id, id);


--
-- Name: preauth_holds fk_preauth_holds_credit_account_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_credit_account_id_currency_account_id FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, credit_account_id, id);


--
-- Name: preauth_holds fk_preauth_holds_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: preauth_holds fk_preauth_holds_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: preauth_holds fk_preauth_holds_currency_account_id_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_currency_account_id_transaction_id FOREIGN KEY (workspace_id, currency_account_id, transaction_id) REFERENCES public.transactions(workspace_id, currency_account_id, id);


--
-- Name: preauth_holds fk_preauth_holds_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: reconciliation_items fk_reconciliation_items_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.reconciliation_items
    ADD CONSTRAINT fk_reconciliation_items_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: recurring_items fk_recurring_items_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.recurring_items
    ADD CONSTRAINT fk_recurring_items_cash_account_id FOREIGN KEY (workspace_id, cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: repayment_allocation_totals fk_repayment_allocation_totals_repayment_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocation_totals
    ADD CONSTRAINT fk_repayment_allocation_totals_repayment_id FOREIGN KEY (workspace_id, repayment_id) REFERENCES public.repayments(workspace_id, id) ON DELETE CASCADE;


--
-- Name: repayment_allocations fk_repayment_allocations_currency_account_id_repayment_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT fk_repayment_allocations_currency_account_id_repayment_id FOREIGN KEY (workspace_id, currency_account_id, repayment_id) REFERENCES public.repayments(workspace_id, currency_account_id, id);


--
-- Name: repayment_allocations fk_repayment_allocations_currency_account_id_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT fk_repayment_allocations_currency_account_id_statement_id FOREIGN KEY (workspace_id, currency_account_id, statement_id) REFERENCES public.statements(workspace_id, currency_account_id, id);


--
-- Name: repayments fk_repayments_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT fk_repayments_cash_account_id FOREIGN KEY (workspace_id, cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: repayments fk_repayments_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT fk_repayments_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: repayments fk_repayments_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT fk_repayments_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: repayments fk_repayments_evidence_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT fk_repayments_evidence_document_id FOREIGN KEY (workspace_id, evidence_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: rule_bindings fk_rule_bindings_billing_rule_version_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT fk_rule_bindings_billing_rule_version_id FOREIGN KEY (billing_rule_version_id) REFERENCES public.billing_rule_versions(id);


--
-- Name: rule_bindings fk_rule_bindings_credit_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT fk_rule_bindings_credit_account_id FOREIGN KEY (workspace_id, credit_account_id) REFERENCES public.credit_accounts(workspace_id, id);


--
-- Name: rule_bindings fk_rule_bindings_credit_account_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT fk_rule_bindings_credit_account_id_currency_account_id FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, credit_account_id, id);


--
-- Name: scenarios fk_scenarios_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.scenarios
    ADD CONSTRAINT fk_scenarios_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: snapshot_included_events fk_snapshot_included_events_cash_account_id_cash_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT fk_snapshot_included_events_cash_account_id_cash_event_id FOREIGN KEY (workspace_id, cash_account_id, cash_event_id) REFERENCES public.cash_events(workspace_id, cash_account_id, id);


--
-- Name: snapshot_included_events fk_snapshot_included_events_cash_account_id_snapshot_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT fk_snapshot_included_events_cash_account_id_snapshot_id FOREIGN KEY (workspace_id, cash_account_id, snapshot_id) REFERENCES public.cash_balance_snapshots(workspace_id, cash_account_id, id) ON DELETE CASCADE;


--
-- Name: source_documents fk_source_documents_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.source_documents
    ADD CONSTRAINT fk_source_documents_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: statement_attributions fk_statement_attributions_currency_account_id_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT fk_statement_attributions_currency_account_id_statement_id FOREIGN KEY (workspace_id, currency_account_id, statement_id) REFERENCES public.statements(workspace_id, currency_account_id, id);


--
-- Name: statement_attributions fk_statement_attributions_currency_account_id_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT fk_statement_attributions_currency_account_id_transaction_id FOREIGN KEY (workspace_id, currency_account_id, transaction_id) REFERENCES public.transactions(workspace_id, currency_account_id, id);


--
-- Name: statement_lines fk_statement_lines_currency_account_id_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT fk_statement_lines_currency_account_id_transaction_id FOREIGN KEY (workspace_id, currency_account_id, transaction_id) REFERENCES public.transactions(workspace_id, currency_account_id, id);


--
-- Name: statement_lines fk_statement_lines_statement_version_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT fk_statement_lines_statement_version_id_currency_account_id FOREIGN KEY (workspace_id, statement_version_id, currency_account_id) REFERENCES public.statement_versions(workspace_id, id, currency_account_id);


--
-- Name: statement_versions fk_statement_versions_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT fk_statement_versions_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: statement_versions fk_statement_versions_statement_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT fk_statement_versions_statement_id_currency_account_id FOREIGN KEY (workspace_id, statement_id, currency_account_id) REFERENCES public.statements(workspace_id, id, currency_account_id);


--
-- Name: statements fk_statements_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT fk_statements_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: statements fk_statements_id_current_version_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT fk_statements_id_current_version_id FOREIGN KEY (workspace_id, id, current_version_id) REFERENCES public.statement_versions(workspace_id, statement_id, id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: sync_changes fk_sync_changes_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_changes
    ADD CONSTRAINT fk_sync_changes_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: sync_conflicts fk_sync_conflicts_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: transaction_links fk_transaction_links_from_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT fk_transaction_links_from_transaction_id FOREIGN KEY (workspace_id, from_transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: transaction_links fk_transaction_links_to_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT fk_transaction_links_to_transaction_id FOREIGN KEY (workspace_id, to_transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: transactions fk_transactions_credit_account_id_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_credit_account_id_card_id FOREIGN KEY (workspace_id, credit_account_id, card_id) REFERENCES public.cards(workspace_id, credit_account_id, id);


--
-- Name: transactions fk_transactions_credit_account_id_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_credit_account_id_currency_account_id FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, credit_account_id, id);


--
-- Name: transactions fk_transactions_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: transactions fk_transactions_currency_account_id_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_currency_account_id_currency FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES public.currency_accounts(workspace_id, id, currency);


--
-- Name: transactions fk_transactions_parent_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_parent_transaction_id FOREIGN KEY (workspace_id, parent_transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: transactions fk_transactions_source_document_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_source_document_id FOREIGN KEY (workspace_id, source_document_id) REFERENCES public.source_documents(workspace_id, id);


--
-- Name: workspace_members fk_workspace_members_user_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT fk_workspace_members_user_id FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: workspace_members fk_workspace_members_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT fk_workspace_members_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: workspaces fk_workspaces_owner_user_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT fk_workspaces_owner_user_id FOREIGN KEY (owner_user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict wGjMgueqooamoyIvRQ1LBqXRnl5bPqXiL7Pi7fDbd42DU3YGn7gOSWu8NuJ5SkJ

