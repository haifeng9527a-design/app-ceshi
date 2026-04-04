// ignore_for_file: avoid_web_libraries_in_flutter

// Web-specific implementation for the lightweight-charts JS bridge.
// This file is only compiled on the web target.

import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Registers an HtmlElementView factory that creates a plain div with [chartId]
/// as its DOM id. Must be called before the view is first rendered.
void registerViewFactory(String viewType, String chartId) {
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final el = html.DivElement()
        ..id = chartId
        ..style.width = '100%'
        ..style.height = '100%';
      return el;
    },
  );
}

/// Calls `window.lwCreate(id, darkMode)` in JS.
void create(String id, bool darkMode) {
  js.context.callMethod('lwCreate', [id, darkMode]);
}

/// Calls `window.lwSetData(id, candleJson, volJson)` in JS.
void setData(String id, String candleJson, String? volJson) {
  js.context.callMethod('lwSetData', [id, candleJson, volJson]);
}

/// Calls `window.lwUpdate(id, candleJson)` in JS.
void update(String id, String candleJson) {
  js.context.callMethod('lwUpdate', [id, candleJson]);
}

/// Calls `window.lwFitContent(id)` in JS.
void fitContent(String id) {
  js.context.callMethod('lwFitContent', [id]);
}

/// Calls `window.lwDestroy(id)` in JS.
void destroy(String id) {
  js.context.callMethod('lwDestroy', [id]);
}

/// Returns the Flutter widget that hosts the native HTML element.
Widget buildHtmlView(String viewType) {
  return HtmlElementView(viewType: viewType);
}
