-- $ docker exec cardflow-dev-db-1 pg_dump -U cardflow --schema-only -d cardflow_test_t005_evidence
-- (temporary database upgraded to head 0001 by evidence/m0/T-005/alembic.txt; dropped afterwards)
--
-- PostgreSQL database dump
--

\restrict hDh4tzNLYgFVPAi5mH0NeMyg31qvXIR6k0Vu99pht8EfHLkO460zvieC9gakzr0

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
-- Name: check_repayment_allocations(uuid); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_repayment_allocations(p_repayment_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_amount bigint;
    v_currency_account_id uuid;
    v_allocated numeric;
BEGIN
    SELECT r.amount_minor, r.currency_account_id
      INTO v_amount, v_currency_account_id
      FROM repayments AS r
     WHERE r.id = p_repayment_id
       FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;  -- the repayment itself is gone; foreign keys report orphans
    END IF;

    SELECT coalesce(sum(a.amount_minor), 0)
      INTO v_allocated
      FROM repayment_allocations AS a
     WHERE a.repayment_id = p_repayment_id
       AND a.deleted_at IS NULL;
    IF v_allocated > v_amount THEN
        RAISE EXCEPTION 'repayment allocations exceed the repayment amount'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_within_amount';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM repayment_allocations AS a
          JOIN statements AS s ON s.id = a.statement_id
         WHERE a.repayment_id = p_repayment_id
           AND a.deleted_at IS NULL
           AND s.currency_account_id <> v_currency_account_id
    ) THEN
        RAISE EXCEPTION 'repayment allocated to a statement of another currency account'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_same_currency_account';
    END IF;
END
$$;


ALTER FUNCTION public.check_repayment_allocations(p_repayment_id uuid) OWNER TO cardflow;

--
-- Name: check_rule_subject_scope(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_rule_subject_scope() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NEW.subject_kind = 'product' THEN
        SELECT EXISTS (
            SELECT 1 FROM card_products AS p
             WHERE p.id = NEW.subject_id
               AND (p.workspace_id IS NULL OR p.workspace_id = NEW.workspace_id)
        ) INTO v_ok;
    ELSIF NEW.subject_kind = 'credit_account' THEN
        SELECT EXISTS (
            SELECT 1 FROM credit_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM currency_accounts AS c
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
-- Name: check_template_scope(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.check_template_scope() RETURNS trigger
    LANGUAGE plpgsql
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
        'SELECT EXISTS (SELECT 1 FROM %I AS t WHERE t.id = $1 '
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
-- Name: forbid_amount_update(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_amount_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'statement_versions amounts are append-only; insert a new version'
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME;
END
$$;


ALTER FUNCTION public.forbid_amount_update() OWNER TO cardflow;

--
-- Name: forbid_statement_version_delete(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_statement_version_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF current_setting('app.purge', true) = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'statement_versions rows are never deleted; set deleted_at instead'
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME,
              HINT = 'A workspace purge runs SELECT set_config(''app.purge'', ''on'', true) '
                     || 'in the same transaction first.';
END
$$;


ALTER FUNCTION public.forbid_statement_version_delete() OWNER TO cardflow;

--
-- Name: forbid_workspace_change(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.forbid_workspace_change() RETURNS trigger
    LANGUAGE plpgsql
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
-- Name: repayment_allocations_check(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.repayment_allocations_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.repayment_id);
    RETURN NULL;
END
$$;


ALTER FUNCTION public.repayment_allocations_check() OWNER TO cardflow;

--
-- Name: repayments_allocation_check(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.repayments_allocation_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.id);
    RETURN NULL;
END
$$;


ALTER FUNCTION public.repayments_allocation_check() OWNER TO cardflow;

--
-- Name: statements_allocation_check(); Type: FUNCTION; Schema: public; Owner: cardflow
--

CREATE FUNCTION public.statements_allocation_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_repayment_id uuid;
BEGIN
    FOR v_repayment_id IN
        SELECT DISTINCT a.repayment_id FROM repayment_allocations AS a WHERE a.statement_id = NEW.id
    LOOP
        PERFORM check_repayment_allocations(v_repayment_id);
    END LOOP;
    RETURN NULL;
END
$$;


ALTER FUNCTION public.statements_allocation_check() OWNER TO cardflow;

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
    CONSTRAINT ck_banks_country_format CHECK ((country ~ '^[A-Z]{2}$'::text))
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
    CONSTRAINT ck_billing_rule_versions_holiday_rollover CHECK ((holiday_rollover = ANY (ARRAY['none'::text, 'next_business_day'::text]))),
    CONSTRAINT ck_billing_rule_versions_review_status CHECK ((review_status = ANY (ARRAY['draft'::text, 'in_review'::text, 'verified'::text, 'published'::text, 'user_declared'::text, 'expired'::text]))),
    CONSTRAINT ck_billing_rule_versions_statement_day_range CHECK (((statement_day >= 1) AND (statement_day <= 31))),
    CONSTRAINT ck_billing_rule_versions_subject_kind CHECK ((subject_kind = ANY (ARRAY['product'::text, 'credit_account'::text, 'currency_account'::text]))),
    CONSTRAINT ck_billing_rule_versions_template_subject CHECK (((workspace_id IS NOT NULL) OR (subject_kind = 'product'::text))),
    CONSTRAINT ck_billing_rule_versions_user_declared_scope CHECK (((review_status <> 'user_declared'::text) OR (workspace_id IS NOT NULL))),
    CONSTRAINT ck_billing_rule_versions_version_positive CHECK ((version >= 1))
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
    origin_device_id uuid
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
    CONSTRAINT ck_cash_events_category CHECK ((category = ANY (ARRAY['income'::text, 'bill'::text, 'living'::text, 'repayment'::text, 'transfer_in'::text, 'transfer_out'::text, 'fee'::text, 'other'::text]))),
    CONSTRAINT ck_cash_events_cls CHECK ((cls = ANY (ARRAY['confirmed'::text, 'expected'::text, 'planned'::text]))),
    CONSTRAINT ck_cash_events_posting_status CHECK ((posting_status = ANY (ARRAY['planned'::text, 'posted'::text])))
);


ALTER TABLE public.cash_events OWNER TO cardflow;

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
    CONSTRAINT ck_charges_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text])))
);


ALTER TABLE public.charges OWNER TO cardflow;

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
-- Name: deletion_tasks; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.deletion_tasks (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    grace_until timestamp with time zone NOT NULL,
    status text NOT NULL,
    executed_at timestamp with time zone,
    CONSTRAINT ck_deletion_tasks_grace_after_request CHECK ((grace_until >= requested_at))
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
    revoked_at timestamp with time zone
);


ALTER TABLE public.devices OWNER TO cardflow;

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
    CONSTRAINT ck_extraction_candidates_confidence_range CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))
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
    CONSTRAINT ck_import_batches_status CHECK ((status = ANY (ARRAY['uploaded'::text, 'parsing'::text, 'needs_review'::text, 'confirmed'::text, 'posted'::text, 'failed'::text, 'rolled_back'::text])))
);


ALTER TABLE public.import_batches OWNER TO cardflow;

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
    CONSTRAINT ck_installment_plans_rounding CHECK ((rounding = ANY (ARRAY['HALF_UP'::text, 'DOWN'::text, 'HALF_EVEN'::text, 'UP'::text])))
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
    CONSTRAINT ck_installment_schedule_principal_non_negative CHECK ((principal_minor >= 0))
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
    CONSTRAINT ck_jobs_attempts_non_negative CHECK ((attempts >= 0)),
    CONSTRAINT ck_jobs_max_attempts_positive CHECK ((max_attempts >= 1)),
    CONSTRAINT ck_jobs_running_has_lease CHECK (((status <> 'running'::text) OR ((locked_by IS NOT NULL) AND (locked_until IS NOT NULL)))),
    CONSTRAINT ck_jobs_status CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'dead'::text]))),
    CONSTRAINT ck_jobs_timeout_positive CHECK ((timeout_s > 0))
);


ALTER TABLE public.jobs OWNER TO cardflow;

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
    CONSTRAINT ck_limit_snapshots_source_kind CHECK ((source_kind = ANY (ARRAY['bank_app'::text, 'statement'::text, 'user'::text, 'import'::text])))
);


ALTER TABLE public.limit_snapshots OWNER TO cardflow;

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
    CONSTRAINT ck_parse_jobs_attempts_non_negative CHECK ((attempts >= 0))
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
    card_id uuid,
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
    CONSTRAINT ck_plan_allocations_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_plan_allocations_due_after_statement CHECK ((due_date > statement_date)),
    CONSTRAINT ck_plan_allocations_fee_non_negative CHECK ((fee_minor >= 0)),
    CONSTRAINT ck_plan_allocations_potential_benefit_non_negative CHECK ((potential_benefit_minor >= 0)),
    CONSTRAINT ck_plan_allocations_verified_benefit_non_negative CHECK ((verified_benefit_minor >= 0))
);


ALTER TABLE public.plan_allocations OWNER TO cardflow;

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
    CONSTRAINT ck_plan_reservations_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_plan_reservations_converted_needs_transaction CHECK (((status <> 'converted'::text) OR (linked_transaction_id IS NOT NULL))),
    CONSTRAINT ck_plan_reservations_status CHECK ((status = ANY (ARRAY['active'::text, 'converted'::text, 'released'::text])))
);


ALTER TABLE public.plan_reservations OWNER TO cardflow;

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
    CONSTRAINT ck_plans_max_cards_positive CHECK ((max_cards >= 1)),
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
    CONSTRAINT ck_preauth_holds_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_preauth_holds_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_preauth_holds_time_precision CHECK ((time_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text])))
);


ALTER TABLE public.preauth_holds OWNER TO cardflow;

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
    CONSTRAINT ck_reconciliation_items_kind CHECK ((kind = ANY (ARRAY['amount_mismatch'::text, 'missing'::text, 'duplicate_txn'::text, 'duplicate_repayment'::text, 'refund_pending'::text, 'unmatched_repayment'::text, 'sync_conflict'::text])))
);


ALTER TABLE public.reconciliation_items OWNER TO cardflow;

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
    CONSTRAINT ck_recurring_items_category CHECK ((category = ANY (ARRAY['income'::text, 'bill'::text, 'living'::text, 'repayment'::text, 'transfer_in'::text, 'transfer_out'::text, 'fee'::text, 'other'::text]))),
    CONSTRAINT ck_recurring_items_cls CHECK ((cls = ANY (ARRAY['confirmed'::text, 'expected'::text, 'planned'::text]))),
    CONSTRAINT ck_recurring_items_ends_after_start CHECK (((ends_on IS NULL) OR (ends_on >= starts_on)))
);


ALTER TABLE public.recurring_items OWNER TO cardflow;

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
    CONSTRAINT ck_repayment_allocations_amount_positive CHECK ((amount_minor > 0))
);


ALTER TABLE public.repayment_allocations OWNER TO cardflow;

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
    CONSTRAINT ck_repayments_amount_positive CHECK ((amount_minor > 0)),
    CONSTRAINT ck_repayments_bank_confirmed_needs_timestamp CHECK (((status <> 'bank_confirmed'::text) OR (bank_confirmed_at IS NOT NULL))),
    CONSTRAINT ck_repayments_status CHECK ((status = ANY (ARRAY['recorded'::text, 'processing'::text, 'cash_debited'::text, 'credit_posted'::text, 'bank_confirmed'::text, 'failed'::text, 'user_marked_paid'::text, 'needs_review'::text, 'reversed'::text])))
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
    CONSTRAINT ck_scenarios_expense_scale_non_negative CHECK ((expense_scale >= (0)::numeric)),
    CONSTRAINT ck_scenarios_income_scale_non_negative CHECK ((income_scale >= (0)::numeric)),
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
    origin_device_id uuid
);


ALTER TABLE public.snapshot_included_events OWNER TO cardflow;

--
-- Name: source_documents; Type: TABLE; Schema: public; Owner: cardflow
--

CREATE TABLE public.source_documents (
    id uuid DEFAULT uuidv7() NOT NULL,
    workspace_id uuid NOT NULL,
    sha256 character(64) NOT NULL,
    mime text NOT NULL,
    size_bytes bigint NOT NULL,
    storage_key text NOT NULL,
    dek_wrapped bytea NOT NULL,
    uploaded_by_device_id uuid,
    retention_until date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    row_version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    origin_device_id uuid,
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
    CONSTRAINT ck_statement_attributions_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text])))
);


ALTER TABLE public.statement_attributions OWNER TO cardflow;

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
    CONSTRAINT ck_statement_lines_card_last4_digits CHECK ((card_last4 ~ '^[0-9]{4}$'::text)),
    CONSTRAINT ck_statement_lines_line_no_positive CHECK ((line_no >= 1))
);


ALTER TABLE public.statement_lines OWNER TO cardflow;

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
    CONSTRAINT ck_statement_versions_source_kind CHECK ((source_kind = ANY (ARRAY['pdf'::text, 'email'::text, 'screenshot'::text, 'csv'::text, 'manual'::text, 'correction'::text]))),
    CONSTRAINT ck_statement_versions_version_no_positive CHECK ((version_no >= 1))
);


ALTER TABLE public.statement_versions OWNER TO cardflow;

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
    CONSTRAINT ck_sync_changes_op CHECK ((op = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);


ALTER TABLE public.sync_changes OWNER TO cardflow;

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
    created_at timestamp with time zone DEFAULT now() NOT NULL
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
    CONSTRAINT ck_transactions_confirmation_level CHECK ((confirmation_level = ANY (ARRAY['system_estimated'::text, 'user_confirmed'::text, 'bank_confirmed'::text]))),
    CONSTRAINT ck_transactions_mcc_digits CHECK ((mcc ~ '^[0-9]{4}$'::text)),
    CONSTRAINT ck_transactions_not_own_parent CHECK (((parent_transaction_id IS NULL) OR (parent_transaction_id <> id))),
    CONSTRAINT ck_transactions_status CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'reversed'::text]))),
    CONSTRAINT ck_transactions_time_precision CHECK ((time_precision = ANY (ARRAY['datetime'::text, 'date'::text, 'month'::text]))),
    CONSTRAINT ck_transactions_txn_type CHECK ((txn_type = ANY (ARRAY['purchase'::text, 'refund'::text, 'reversal'::text, 'cash_advance'::text, 'fee'::text, 'interest'::text, 'repayment'::text, 'transfer'::text, 'preauth'::text, 'installment_principal'::text, 'adjustment'::text])))
);


ALTER TABLE public.transactions OWNER TO cardflow;

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
    CONSTRAINT ck_users_email_lowercase CHECK ((email = lower(email))),
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
    ADD CONSTRAINT pk_plan_allocations PRIMARY KEY (run_id, currency_account_id);


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
-- Name: repayment_allocations pk_repayment_allocations; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT pk_repayment_allocations PRIMARY KEY (repayment_id, statement_id);


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
    ADD CONSTRAINT pk_snapshot_included_events PRIMARY KEY (snapshot_id, cash_event_id);


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
-- Name: cash_balance_snapshots uq_cash_balance_snapshots_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_balance_snapshots
    ADD CONSTRAINT uq_cash_balance_snapshots_workspace_id_id UNIQUE (workspace_id, id);


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
-- Name: credit_pool_members uq_credit_pool_members_pool_id_credit_account_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.credit_pool_members
    ADD CONSTRAINT uq_credit_pool_members_pool_id_credit_account_id UNIQUE (pool_id, credit_account_id);


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
-- Name: currency_accounts uq_currency_accounts_credit_account_id_currency; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT uq_currency_accounts_credit_account_id_currency UNIQUE (credit_account_id, currency);


--
-- Name: currency_accounts uq_currency_accounts_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.currency_accounts
    ADD CONSTRAINT uq_currency_accounts_workspace_id_id UNIQUE (workspace_id, id);


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
-- Name: installment_schedule uq_installment_schedule_plan_id_period_no; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT uq_installment_schedule_plan_id_period_no UNIQUE (plan_id, period_no);


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
-- Name: plan_run_checks uq_plan_run_checks_run_id_scenario_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_run_checks
    ADD CONSTRAINT uq_plan_run_checks_run_id_scenario_id UNIQUE (run_id, scenario_id);


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
-- Name: plans uq_plans_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT uq_plans_workspace_id_id UNIQUE (workspace_id, id);


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
-- Name: source_documents uq_source_documents_workspace_id_sha256; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.source_documents
    ADD CONSTRAINT uq_source_documents_workspace_id_sha256 UNIQUE (workspace_id, sha256);


--
-- Name: statement_attributions uq_statement_attributions_transaction_id_statement_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT uq_statement_attributions_transaction_id_statement_id UNIQUE (transaction_id, statement_id);


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
-- Name: statement_versions uq_statement_versions_workspace_id_statement_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT uq_statement_versions_workspace_id_statement_id_id UNIQUE (workspace_id, statement_id, id);


--
-- Name: statements uq_statements_currency_account_id_statement_date; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT uq_statements_currency_account_id_statement_date UNIQUE (currency_account_id, statement_date);


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
-- Name: transaction_links uq_transaction_links_from_transaction_id_to_transaction_id_kind; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT uq_transaction_links_from_transaction_id_to_transaction_id_kind UNIQUE (from_transaction_id, to_transaction_id, kind);


--
-- Name: transaction_links uq_transaction_links_workspace_id_id; Type: CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transaction_links
    ADD CONSTRAINT uq_transaction_links_workspace_id_id UNIQUE (workspace_id, id);


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
-- Name: ix_charges_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_charges_currency_account_id ON public.charges USING btree (currency_account_id);


--
-- Name: ix_consents_workspace_id_purpose; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_consents_workspace_id_purpose ON public.consents USING btree (workspace_id, purpose);


--
-- Name: ix_credit_accounts_bank_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_accounts_bank_id ON public.credit_accounts USING btree (bank_id);


--
-- Name: ix_credit_pool_members_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_credit_pool_members_credit_account_id ON public.credit_pool_members USING btree (credit_account_id);


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
-- Name: ix_jobs_status_run_after; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_jobs_status_run_after ON public.jobs USING btree (status, run_after) WHERE (status = 'queued'::text);


--
-- Name: ix_limit_adjustments_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_adjustments_currency_account_id ON public.limit_adjustments USING btree (currency_account_id);


--
-- Name: ix_limit_snapshots_currency_account_id_balance_as_of; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_limit_snapshots_currency_account_id_balance_as_of ON public.limit_snapshots USING btree (currency_account_id, balance_as_of DESC);


--
-- Name: ix_parse_jobs_source_document_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_parse_jobs_source_document_id ON public.parse_jobs USING btree (source_document_id);


--
-- Name: ix_plan_invalidations_plan_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_invalidations_plan_id ON public.plan_invalidations USING btree (plan_id);


--
-- Name: ix_plan_reservations_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_currency_account_id ON public.plan_reservations USING btree (currency_account_id);


--
-- Name: ix_plan_reservations_plan_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_reservations_plan_id ON public.plan_reservations USING btree (plan_id);


--
-- Name: ix_plan_runs_plan_id_created_at; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_plan_runs_plan_id_created_at ON public.plan_runs USING btree (plan_id, created_at);


--
-- Name: ix_preauth_holds_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_preauth_holds_currency_account_id ON public.preauth_holds USING btree (currency_account_id);


--
-- Name: ix_reconciliation_items_workspace_id_status; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_reconciliation_items_workspace_id_status ON public.reconciliation_items USING btree (workspace_id, status);


--
-- Name: ix_recurring_items_cash_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_recurring_items_cash_account_id ON public.recurring_items USING btree (cash_account_id);


--
-- Name: ix_repayment_allocations_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayment_allocations_statement_id ON public.repayment_allocations USING btree (statement_id);


--
-- Name: ix_repayments_currency_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_repayments_currency_account_id ON public.repayments USING btree (currency_account_id);


--
-- Name: ix_rule_bindings_billing_rule_version_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_rule_bindings_billing_rule_version_id ON public.rule_bindings USING btree (billing_rule_version_id);


--
-- Name: ix_rule_bindings_credit_account_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_rule_bindings_credit_account_id ON public.rule_bindings USING btree (credit_account_id);


--
-- Name: ix_snapshot_included_events_cash_event_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_snapshot_included_events_cash_event_id ON public.snapshot_included_events USING btree (cash_event_id);


--
-- Name: ix_statement_attributions_statement_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_attributions_statement_id ON public.statement_attributions USING btree (statement_id);


--
-- Name: ix_statement_lines_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_statement_lines_transaction_id ON public.statement_lines USING btree (transaction_id);


--
-- Name: ix_sync_changes_workspace_id_seq; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_sync_changes_workspace_id_seq ON public.sync_changes USING btree (workspace_id, seq);


--
-- Name: ix_sync_conflicts_workspace_id_table_name_row_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_sync_conflicts_workspace_id_table_name_row_id ON public.sync_conflicts USING btree (workspace_id, table_name, row_id);


--
-- Name: ix_transaction_links_to_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transaction_links_to_transaction_id ON public.transaction_links USING btree (to_transaction_id);


--
-- Name: ix_transactions_currency_account_id_posted_on; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_currency_account_id_posted_on ON public.transactions USING btree (currency_account_id, posted_on);


--
-- Name: ix_transactions_merchant_trgm; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE INDEX ix_transactions_merchant_trgm ON public.transactions USING gin (merchant public.gin_trgm_ops);


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
-- Name: uq_currency_accounts_one_primary; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_currency_accounts_one_primary ON public.currency_accounts USING btree (credit_account_id) WHERE (is_primary AND (deleted_at IS NULL));


--
-- Name: uq_installment_plans_transaction_id; Type: INDEX; Schema: public; Owner: cardflow
--

CREATE UNIQUE INDEX uq_installment_plans_transaction_id ON public.installment_plans USING btree (transaction_id) WHERE (deleted_at IS NULL);


--
-- Name: banks banks_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER banks_workspace_immutable BEFORE UPDATE OF workspace_id ON public.banks FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


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
-- Name: card_products card_products_workspace_immutable; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER card_products_workspace_immutable BEFORE UPDATE OF workspace_id ON public.card_products FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change();


--
-- Name: credit_accounts credit_accounts_bank_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_bank_scope BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('bank_id', 'banks');


--
-- Name: credit_accounts credit_accounts_product_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_accounts_product_scope BEFORE INSERT OR UPDATE OF workspace_id, product_id ON public.credit_accounts FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('product_id', 'card_products');


--
-- Name: credit_pools credit_pools_bank_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER credit_pools_bank_scope BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('bank_id', 'banks');


--
-- Name: repayment_allocations repayment_allocations_within_amount; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE CONSTRAINT TRIGGER repayment_allocations_within_amount AFTER INSERT OR UPDATE ON public.repayment_allocations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.repayment_allocations_check();


--
-- Name: repayments repayments_allocations_within_amount; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE CONSTRAINT TRIGGER repayments_allocations_within_amount AFTER UPDATE OF amount_minor, currency_account_id ON public.repayments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.repayments_allocation_check();


--
-- Name: rule_bindings rule_bindings_rule_version_scope; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER rule_bindings_rule_version_scope BEFORE INSERT OR UPDATE OF workspace_id, billing_rule_version_id ON public.rule_bindings FOR EACH ROW EXECUTE FUNCTION public.check_template_scope('billing_rule_version_id', 'billing_rule_versions');


--
-- Name: statement_versions statement_versions_append_only; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_append_only BEFORE UPDATE OF previous_balance_minor, new_balance_minor, min_due_minor, payments_minor, credits_minor, fees_minor, interest_minor, installment_due_minor, credit_balance_minor, due_date ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_amount_update();


--
-- Name: statement_versions statement_versions_no_delete; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_no_delete BEFORE DELETE ON public.statement_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_statement_version_delete();


--
-- Name: statement_versions statement_versions_no_truncate; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE TRIGGER statement_versions_no_truncate BEFORE TRUNCATE ON public.statement_versions FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_statement_version_delete();


--
-- Name: statements statements_allocations_same_currency_account; Type: TRIGGER; Schema: public; Owner: cardflow
--

CREATE CONSTRAINT TRIGGER statements_allocations_same_currency_account AFTER UPDATE OF currency_account_id ON public.statements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.statements_allocation_check();


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
-- Name: cash_events fk_cash_events_linked_plan_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_linked_plan_run_id FOREIGN KEY (workspace_id, linked_plan_run_id) REFERENCES public.plan_runs(workspace_id, id);


--
-- Name: cash_events fk_cash_events_linked_repayment_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_linked_repayment_id FOREIGN KEY (workspace_id, linked_repayment_id) REFERENCES public.repayments(workspace_id, id);


--
-- Name: cash_events fk_cash_events_recurring_item_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_events
    ADD CONSTRAINT fk_cash_events_recurring_item_id FOREIGN KEY (workspace_id, recurring_item_id) REFERENCES public.recurring_items(workspace_id, id);


--
-- Name: cash_transfers fk_cash_transfers_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: cash_transfers fk_cash_transfers_from_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_from_cash_account_id FOREIGN KEY (workspace_id, from_cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: cash_transfers fk_cash_transfers_in_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_in_event_id FOREIGN KEY (workspace_id, in_event_id) REFERENCES public.cash_events(workspace_id, id);


--
-- Name: cash_transfers fk_cash_transfers_out_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_out_event_id FOREIGN KEY (workspace_id, out_event_id) REFERENCES public.cash_events(workspace_id, id);


--
-- Name: cash_transfers fk_cash_transfers_to_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.cash_transfers
    ADD CONSTRAINT fk_cash_transfers_to_cash_account_id FOREIGN KEY (workspace_id, to_cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: charges fk_charges_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: charges fk_charges_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: charges fk_charges_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_statement_id FOREIGN KEY (workspace_id, statement_id) REFERENCES public.statements(workspace_id, id);


--
-- Name: charges fk_charges_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_charges_transaction_id FOREIGN KEY (workspace_id, transaction_id) REFERENCES public.transactions(workspace_id, id);


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
-- Name: limit_snapshots fk_limit_snapshots_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.limit_snapshots
    ADD CONSTRAINT fk_limit_snapshots_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


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
-- Name: plan_allocations fk_plan_allocations_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_card_id FOREIGN KEY (workspace_id, card_id) REFERENCES public.cards(workspace_id, id);


--
-- Name: plan_allocations fk_plan_allocations_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: plan_allocations fk_plan_allocations_repay_from_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_repay_from_cash_account_id FOREIGN KEY (workspace_id, repay_from_cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: plan_allocations fk_plan_allocations_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_allocations
    ADD CONSTRAINT fk_plan_allocations_run_id FOREIGN KEY (workspace_id, run_id) REFERENCES public.plan_runs(workspace_id, id);


--
-- Name: plan_invalidations fk_plan_invalidations_plan_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT fk_plan_invalidations_plan_id FOREIGN KEY (workspace_id, plan_id) REFERENCES public.plans(workspace_id, id);


--
-- Name: plan_invalidations fk_plan_invalidations_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_invalidations
    ADD CONSTRAINT fk_plan_invalidations_run_id FOREIGN KEY (workspace_id, run_id) REFERENCES public.plan_runs(workspace_id, id);


--
-- Name: plan_reservations fk_plan_reservations_cash_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_cash_account_id FOREIGN KEY (workspace_id, cash_account_id) REFERENCES public.cash_accounts(workspace_id, id);


--
-- Name: plan_reservations fk_plan_reservations_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: plan_reservations fk_plan_reservations_linked_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_linked_transaction_id FOREIGN KEY (workspace_id, linked_transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: plan_reservations fk_plan_reservations_plan_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_plan_id FOREIGN KEY (workspace_id, plan_id) REFERENCES public.plans(workspace_id, id);


--
-- Name: plan_reservations fk_plan_reservations_run_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_reservations
    ADD CONSTRAINT fk_plan_reservations_run_id FOREIGN KEY (workspace_id, run_id) REFERENCES public.plan_runs(workspace_id, id);


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
-- Name: plan_runs fk_plan_runs_plan_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.plan_runs
    ADD CONSTRAINT fk_plan_runs_plan_id FOREIGN KEY (workspace_id, plan_id) REFERENCES public.plans(workspace_id, id);


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
-- Name: preauth_holds fk_preauth_holds_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_card_id FOREIGN KEY (workspace_id, card_id) REFERENCES public.cards(workspace_id, id);


--
-- Name: preauth_holds fk_preauth_holds_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: preauth_holds fk_preauth_holds_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: preauth_holds fk_preauth_holds_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.preauth_holds
    ADD CONSTRAINT fk_preauth_holds_transaction_id FOREIGN KEY (workspace_id, transaction_id) REFERENCES public.transactions(workspace_id, id);


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
-- Name: repayment_allocations fk_repayment_allocations_repayment_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT fk_repayment_allocations_repayment_id FOREIGN KEY (workspace_id, repayment_id) REFERENCES public.repayments(workspace_id, id);


--
-- Name: repayment_allocations fk_repayment_allocations_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayment_allocations
    ADD CONSTRAINT fk_repayment_allocations_statement_id FOREIGN KEY (workspace_id, statement_id) REFERENCES public.statements(workspace_id, id);


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
-- Name: repayments fk_repayments_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.repayments
    ADD CONSTRAINT fk_repayments_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


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
-- Name: rule_bindings fk_rule_bindings_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.rule_bindings
    ADD CONSTRAINT fk_rule_bindings_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: scenarios fk_scenarios_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.scenarios
    ADD CONSTRAINT fk_scenarios_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: snapshot_included_events fk_snapshot_included_events_cash_event_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT fk_snapshot_included_events_cash_event_id FOREIGN KEY (workspace_id, cash_event_id) REFERENCES public.cash_events(workspace_id, id);


--
-- Name: snapshot_included_events fk_snapshot_included_events_snapshot_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.snapshot_included_events
    ADD CONSTRAINT fk_snapshot_included_events_snapshot_id FOREIGN KEY (workspace_id, snapshot_id) REFERENCES public.cash_balance_snapshots(workspace_id, id) ON DELETE CASCADE;


--
-- Name: source_documents fk_source_documents_workspace_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.source_documents
    ADD CONSTRAINT fk_source_documents_workspace_id FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: statement_attributions fk_statement_attributions_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT fk_statement_attributions_statement_id FOREIGN KEY (workspace_id, statement_id) REFERENCES public.statements(workspace_id, id);


--
-- Name: statement_attributions fk_statement_attributions_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_attributions
    ADD CONSTRAINT fk_statement_attributions_transaction_id FOREIGN KEY (workspace_id, transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: statement_lines fk_statement_lines_statement_version_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT fk_statement_lines_statement_version_id FOREIGN KEY (workspace_id, statement_version_id) REFERENCES public.statement_versions(workspace_id, id);


--
-- Name: statement_lines fk_statement_lines_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_lines
    ADD CONSTRAINT fk_statement_lines_transaction_id FOREIGN KEY (workspace_id, transaction_id) REFERENCES public.transactions(workspace_id, id);


--
-- Name: statement_versions fk_statement_versions_statement_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.statement_versions
    ADD CONSTRAINT fk_statement_versions_statement_id FOREIGN KEY (workspace_id, statement_id) REFERENCES public.statements(workspace_id, id);


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
-- Name: transactions fk_transactions_card_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_card_id FOREIGN KEY (workspace_id, card_id) REFERENCES public.cards(workspace_id, id);


--
-- Name: transactions fk_transactions_currency; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_currency FOREIGN KEY (currency) REFERENCES public.currencies(code);


--
-- Name: transactions fk_transactions_currency_account_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_currency_account_id FOREIGN KEY (workspace_id, currency_account_id) REFERENCES public.currency_accounts(workspace_id, id);


--
-- Name: transactions fk_transactions_parent_transaction_id; Type: FK CONSTRAINT; Schema: public; Owner: cardflow
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_parent_transaction_id FOREIGN KEY (workspace_id, parent_transaction_id) REFERENCES public.transactions(workspace_id, id);


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

\unrestrict hDh4tzNLYgFVPAi5mH0NeMyg31qvXIR6k0Vu99pht8EfHLkO460zvieC9gakzr0

