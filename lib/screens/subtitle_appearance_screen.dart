import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';

class SubtitleAppearanceScreen extends StatefulWidget {
  const SubtitleAppearanceScreen({super.key});

  @override
  State<SubtitleAppearanceScreen> createState() => _SubtitleAppearanceScreenState();
}

class _SubtitleAppearanceScreenState extends State<SubtitleAppearanceScreen> {
  // Subtitle styling state
  int _textSizeIndex = 1; // 0: Small, 1: Medium, 2: Large
  String _textColor = 'White';
  String _edgeStyle = 'Drop Shadow';
  String _edgeColor = 'Black';
  String _bgColor = 'None';
  bool _bgTransparent = true;
  String _windowColor = 'None';
  bool _windowTransparent = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _textSizeIndex = prefs.getInt('sub_text_size_index') ?? 1;
      _textColor = prefs.getString('sub_text_color') ?? 'White';
      _edgeStyle = prefs.getString('sub_edge_style') ?? 'Drop Shadow';
      _edgeColor = prefs.getString('sub_edge_color') ?? 'Black';
      _bgColor = prefs.getString('sub_bg_color') ?? 'None';
      _bgTransparent = prefs.getBool('sub_bg_transparent') ?? true;
      _windowColor = prefs.getString('sub_window_color') ?? 'None';
      _windowTransparent = prefs.getBool('sub_window_transparent') ?? true;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sub_text_size_index', _textSizeIndex);
    await prefs.setString('sub_text_color', _textColor);
    await prefs.setString('sub_edge_style', _edgeStyle);
    await prefs.setString('sub_edge_color', _edgeColor);
    await prefs.setString('sub_bg_color', _bgColor);
    await prefs.setBool('sub_bg_transparent', _bgTransparent);
    await prefs.setString('sub_window_color', _windowColor);
    await prefs.setBool('sub_window_transparent', _windowTransparent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subtitle appearance saved.'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _textSizeIndex = 1;
      _textColor = 'White';
      _edgeStyle = 'Drop Shadow';
      _edgeColor = 'Black';
      _bgColor = 'None';
      _bgTransparent = true;
      _windowColor = 'None';
      _windowTransparent = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sub_text_size_index');
    await prefs.remove('sub_text_color');
    await prefs.remove('sub_edge_style');
    await prefs.remove('sub_edge_color');
    await prefs.remove('sub_bg_color');
    await prefs.remove('sub_bg_transparent');
    await prefs.remove('sub_window_color');
    await prefs.remove('sub_window_transparent');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset to default subtitle settings.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  double _getFontSize() {
    switch (_textSizeIndex) {
      case 0:
        return 13.0;
      case 2:
        return 20.0;
      case 1:
      default:
        return 16.0;
    }
  }

  Color _resolveColor(String name) {
    switch (name) {
      case 'Yellow':
        return Colors.yellowAccent;
      case 'Cyan':
        return Colors.cyanAccent;
      case 'Green':
        return Colors.greenAccent;
      case 'Magenta':
        return Colors.pinkAccent;
      case 'Red':
        return Colors.redAccent;
      case 'Black':
        return Colors.black;
      case 'White':
      default:
        return Colors.white;
    }
  }

  List<Shadow> _getEdgeShadows() {
    final edgeCol = _resolveColor(_edgeColor);
    switch (_edgeStyle) {
      case 'Drop Shadow':
        return [
          Shadow(color: edgeCol.withValues(alpha: 0.9), offset: const Offset(2, 2), blurRadius: 4),
        ];
      case 'Raised':
        return [
          Shadow(color: Colors.white70, offset: const Offset(-1, -1), blurRadius: 1),
          Shadow(color: edgeCol, offset: const Offset(1, 1), blurRadius: 2),
        ];
      case 'Depressed':
        return [
          Shadow(color: edgeCol, offset: const Offset(-1, -1), blurRadius: 1),
          Shadow(color: Colors.white70, offset: const Offset(1, 1), blurRadius: 2),
        ];
      case 'Uniform (Outline)':
        return [
          Shadow(color: edgeCol, offset: const Offset(-1.5, -1.5), blurRadius: 1),
          Shadow(color: edgeCol, offset: const Offset(1.5, -1.5), blurRadius: 1),
          Shadow(color: edgeCol, offset: const Offset(-1.5, 1.5), blurRadius: 1),
          Shadow(color: edgeCol, offset: const Offset(1.5, 1.5), blurRadius: 1),
        ];
      case 'None':
      default:
        return [];
    }
  }

  void _showColorPicker({
    required String title,
    required String current,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(color: Colors.white12),
            ...options.map((opt) {
              final isSel = opt == current;
              return ListTile(
                title: Text(opt, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                trailing: isSel ? const Icon(Icons.check, color: AppTheme.primaryRed) : null,
                onTap: () {
                  onSelected(opt);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Subtitle Appearance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Top descriptive subtitle
          const Text(
            'Change the way subtitles appear on phones and tablets.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Live Preview Cloud Box (Screenshot 4)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF3B82F6), // Blue sky
                    Color(0xFF93C5FD), // Light cloud blue
                    Color(0xFFE2E8F0), // Cloud white
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bgColor == 'None'
                        ? Colors.transparent
                        : _resolveColor(_bgColor).withValues(alpha: _bgTransparent ? 0.6 : 1.0),
                    borderRadius: BorderRadius.circular(6),
                    border: _windowColor == 'None'
                        ? null
                        : Border.all(
                            color: _resolveColor(_windowColor).withValues(alpha: _windowTransparent ? 0.6 : 1.0),
                            width: 2,
                          ),
                  ),
                  child: Text(
                    'These settings affect subtitles on phones and tablets.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _getFontSize(),
                      color: _resolveColor(_textColor),
                      fontWeight: FontWeight.w600,
                      shadows: _getEdgeShadows(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 1. Text Size (3 segmented boxes: A A A)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Text Size', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF22222E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      _buildSizeOption(0, 'A', 13),
                      _buildSizeOption(1, 'A', 16),
                      _buildSizeOption(2, 'A', 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. Text Color
          _buildSelectRow(
            title: 'Text Color',
            value: _textColor,
            onTap: () {
              _showColorPicker(
                title: 'Text Color',
                current: _textColor,
                options: ['White', 'Yellow', 'Cyan', 'Green', 'Magenta', 'Red', 'Black'],
                onSelected: (val) => setState(() => _textColor = val),
              );
            },
          ),
          const SizedBox(height: 10),

          // 3. Text Edge Style
          _buildSelectRow(
            title: 'Text Edge Style',
            value: _edgeStyle,
            onTap: () {
              _showColorPicker(
                title: 'Text Edge Style',
                current: _edgeStyle,
                options: ['Drop Shadow', 'Raised', 'Depressed', 'Uniform (Outline)', 'None'],
                onSelected: (val) => setState(() => _edgeStyle = val),
              );
            },
          ),
          const SizedBox(height: 10),

          // 4. Text Edge Color
          _buildSelectRow(
            title: 'Text Edge Color',
            value: _edgeColor,
            onTap: () {
              _showColorPicker(
                title: 'Text Edge Color',
                current: _edgeColor,
                options: ['Black', 'White', 'Red', 'Yellow', 'Cyan'],
                onSelected: (val) => setState(() => _edgeColor = val),
              );
            },
          ),
          const SizedBox(height: 10),

          // 5. Background Color
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Background Color', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    GestureDetector(
                      onTap: () {
                        _showColorPicker(
                          title: 'Background Color',
                          current: _bgColor,
                          options: ['None', 'Black', 'White', 'Cyan', 'Yellow', 'Red'],
                          onSelected: (val) => setState(() => _bgColor = val),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_bgColor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Transparency', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Switch(
                      value: _bgTransparent,
                      activeThumbColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => _bgTransparent = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 6. Window Color
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Window Color', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    GestureDetector(
                      onTap: () {
                        _showColorPicker(
                          title: 'Window Color',
                          current: _windowColor,
                          options: ['None', 'Black', 'White', 'Red', 'Yellow'],
                          onSelected: (val) => setState(() => _windowColor = val),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_windowColor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Transparency', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Switch(
                      value: _windowTransparent,
                      activeThumbColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => _windowTransparent = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Bottom Action Buttons: Save & Reset to default (Screenshot 4)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A38),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _savePreferences,
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A38),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _resetToDefault,
                  child: const Text('Reset to default', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildSizeOption(int index, String label, double fontSize) {
    final isSel = _textSizeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _textSizeIndex = index),
      child: Container(
        width: 44,
        height: 38,
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF4A4A5A) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectRow({required String title, required String value, required VoidCallback onTap}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: value == 'White' ? Colors.white : const Color(0xFF2A2A38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: value == 'White' ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
