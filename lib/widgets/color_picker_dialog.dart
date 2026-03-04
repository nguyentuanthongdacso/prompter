import 'package:flutter/material.dart';
import '../models/prompter_settings.dart';

class ColorPickerDialog extends StatelessWidget {
  final Color initialColor;
  final String title;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    this.title = 'Chọn màu',
  });

  @override
  Widget build(BuildContext context) {
    final colors = PrompterSettings.presetColorsWithNames;
    
    return SimpleDialog(
      title: Text(title),
      children: colors.map((item) {
        final color = item['color'] as Color;
        final name = item['name'] as String;
        final isSelected = initialColor.value == color.value;
        final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
        
        return SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(color),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade400,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Row(
              children: [
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: luminance > 0.5 ? Colors.black : Colors.white,
                  ),
                if (isSelected) const SizedBox(width: 8),
                Text(
                  name,
                  style: TextStyle(
                    color: luminance > 0.5 ? Colors.black : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
