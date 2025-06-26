import 'package:flutter/material.dart';
import 'package:indrive/login_screen.dart'; // We will create this file

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indrive Clone',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginScreen(), // Set LoginScreen as the initial screen
    );
  }
}
