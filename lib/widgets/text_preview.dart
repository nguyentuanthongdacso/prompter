import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prompter_settings.dart';

class TextPreview extends StatelessWidget {
  const TextPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PrompterSettings>(
      builder: (context, settings, child) {
        return Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: settings.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: settings.paddingHorizontal,
            vertical: 16,
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(settings.mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
            child: SingleChildScrollView(
              child: Text(
                settings.text.isEmpty ? 'Xem trước văn bản...' : settings.text,
                style: settings.getTextStyle(),
                textAlign: settings.textAlign,
              ),
            ),
          ),
        );
      },
    );
  }
}
