import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开外部链接前确认。
Future<void> launchUrlExternal(Uri url, {BuildContext? context}) async {
  var ok = true;
  if (context != null && context.mounted) {
    ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('打开外部链接？'),
            content: SelectableText(
              url.toString(),
              style: const TextStyle(color: Colors.blue),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('打开'),
              ),
            ],
          ),
        ) ??
        false;
  }
  if (ok) await launchUrl(url);
}
