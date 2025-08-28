import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppText {
  // Headings with iUrbanist
  static TextStyle heading1 = GoogleFonts.urbanist(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static TextStyle heading2 = GoogleFonts.urbanist(
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );

  // Subtexts with Poppins
  static TextStyle subtitle1 = GoogleFonts.poppins(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static TextStyle subtitle2 = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static TextStyle bodyText = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}