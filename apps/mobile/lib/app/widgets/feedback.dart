import 'package:flutter/material.dart';

/// ui-spec §2"成功"：≤4 秒的轻提示。新提示直接替换正在显示的提示，不排队等待。
void showFeedback(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: const Duration(seconds: 4),
      ),
    );
}
