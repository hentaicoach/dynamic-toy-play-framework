import 'package:flutter/material.dart';
import 'app.dart';
import 'config/constants.dart';
import 'package:yokonex_play/config/constants.dart';

void main() {
  // 设置日志级别（INFO 级，不输出 DEBUG 日志）
  Log.setLevel(LogLevel.info);
  runApp(const YokonexPlayApp());
}
