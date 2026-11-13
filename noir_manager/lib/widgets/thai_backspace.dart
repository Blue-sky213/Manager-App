import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// สระ/วรรณยุกต์ไทยที่ซ้อนบน-ล่างตัวอักษร (ไม้หันอากาศ · สระบน/ล่าง · ไม้ไต่คู้ · วรรณยุกต์ · การันต์ ฯลฯ)
bool isThaiMark(int rune) => rune == 0x0E31 || (rune >= 0x0E34 && rune <= 0x0E3A) || (rune >= 0x0E47 && rune <= 0x0E4E);

/// ลบ 1 ครั้งด้วย Backspace: ถ้าตัวก่อนเคอร์เซอร์เป็นสระ/วรรณยุกต์ไทย → ลบแค่ตัวนั้น
/// (Flutter ลบทั้งกลุ่ม เช่น "กิ" หายทั้งคู่) · คืน null = ให้ระบบลบตามปกติ
TextEditingValue? thaiBackspace(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed || sel.baseOffset <= 0) return null;
  final before = v.text.substring(0, sel.baseOffset);
  final rune = before.runes.last;
  if (!isThaiMark(rune)) return null;
  final cut = before.length - (rune > 0xFFFF ? 2 : 1);
  return TextEditingValue(
    text: v.text.substring(0, cut) + v.text.substring(sel.baseOffset),
    selection: TextSelection.collapsed(offset: cut),
  );
}

class _ThaiBackspaceIntent extends Intent {
  const _ThaiBackspaceIntent();
}

/// ครอบทั้งแอป: ดัก Backspace ก่อนช่องพิมพ์ · ลบสระไทยทีละตัว · กรณีอื่นส่งต่อให้ช่องพิมพ์ลบตามเดิม
class ThaiBackspace extends StatelessWidget {
  const ThaiBackspace({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.backspace): _ThaiBackspaceIntent()},
        child: Actions(
          actions: {_ThaiBackspaceIntent: _ThaiBackspaceAction()},
          child: child,
        ),
      );
}

class _ThaiBackspaceAction extends ContextAction<_ThaiBackspaceIntent> {
  EditableTextState? get _editor => primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();

  // ไม่ได้อยู่ในช่องพิมพ์ → ปล่อยให้ Backspace ทำงานอย่างอื่นตามปกติ
  @override
  bool isEnabled(_ThaiBackspaceIntent intent, [BuildContext? context]) => _editor != null;

  @override
  bool consumesKey(_ThaiBackspaceIntent intent) => true;

  @override
  Object? invoke(_ThaiBackspaceIntent intent, [BuildContext? context]) {
    final editor = _editor;
    if (editor == null) return null;
    final next = thaiBackspace(editor.textEditingValue);
    if (next != null && !editor.widget.readOnly) {
      editor.userUpdateTextEditingValue(next, SelectionChangedCause.keyboard);
      return null;
    }
    // ไม่ใช่สระไทย → ให้ช่องพิมพ์ลบตามปกติ (ทีละตัวอักษร / ลบที่เลือกไว้)
    final ctx = primaryFocus?.context;
    if (ctx != null) Actions.maybeInvoke(ctx, const DeleteCharacterIntent(forward: false));
    return null;
  }
}
