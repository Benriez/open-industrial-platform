import 'package:flutter/material.dart';

/// Whether a **text field** of the surface owns the keyboard right now.
///
/// The shortcuts of a workstation — the pin, the comparison, the search — are
/// keys of the page, but only while no text field is edited. A field of the
/// inspector is a field of the page too: without this question the handler of
/// the page swallows the keys of the field, and the operator loses the
/// characters that the shortcuts use (the letter "c" toggled the comparison
/// instead of being written into the note of the device).
bool aTextFieldHasTheFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}
