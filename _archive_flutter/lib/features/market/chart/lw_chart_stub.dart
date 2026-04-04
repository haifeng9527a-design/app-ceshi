// Stub implementation for non-web platforms.
// All functions are no-ops so that tree-shaking removes them on mobile builds.

import 'package:flutter/material.dart';

void registerViewFactory(String viewType, String chartId) {}

void create(String id, bool darkMode) {}

void setData(String id, String candleJson, String? volJson) {}

void update(String id, String candleJson) {}

void fitContent(String id) {}

void destroy(String id) {}

Widget buildHtmlView(String viewType) => const SizedBox.shrink();
