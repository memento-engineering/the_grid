import 'package:flutter/material.dart';

import '../models/view_state.dart';

/// Resolves a semantic severity against the active Material color scheme.
Color severityColor(ColorScheme colors, SeverityToken severity) =>
    switch (severity) {
      SeverityToken.fine => colors.outline,
      SeverityToken.info => colors.primary,
      SeverityToken.warning => colors.tertiary,
      SeverityToken.error => colors.error,
    };
