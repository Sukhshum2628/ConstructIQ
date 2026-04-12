import 'package:flutter/material.dart';

/// 🧠 MASTER VISUAL CONTROL PANEL (Project Details Page)
/// This file is purely for visual tweaks. Modifying these values 
/// will NOT break any backend functionality or database connections.
class ProjectDetailUI {
  
  // ===================================================================
  // 🏷️ GLOBAL SECTION TITLES (e.g., "Project Timeline", "Material Estimations")
  // ===================================================================
  static const double sectionTitleFontSize = 16.0;
  static const FontWeight sectionTitleWeight = FontWeight.bold;
  static const Color sectionTitleColor = Color(0xFF003E7E); // DFColors.primaryContainerStitch
  static const double sectionTitleBottomPadding = 16.0;
  static const double sectionTitleTopMargin = 27.0; // Gap between sections

  // ===================================================================
  // 🧭 NAVIGATION & APP BAR
  // ===================================================================
  static const double appBarLeadingWidth = 40.0;
  static const double arrowToTitleGap = 4.0;
  static const double titleFontSize = 24.0;
  static const FontWeight titleWeight = FontWeight.bold;
  static const double titleLetterSpacing = -0.5;
  static const double iconGap = 1.0;
  static const double sectionBulletSize = 8.0;      // New: Bullet point size
  static const double sectionBulletGap = 8.0;       // New: Space after bullet
  static const double actionsRightPadding = 20.0;
  
  // ===================================================================
  // 📦 PROJECT HEADER BLOCK (The Bordered Rectangle)
  // ===================================================================
  static const double blockBorderWidth = 1.5;
  static const double blockBorderRadius = 12.0;
  static const double blockPaddingTop = 24.0;
  static const double blockPaddingBottom = 16.0;
  static const double blockPaddingSides = 16.0;
  
  // 📈 PROGRESS BADGE (On the border)
  static const double badgeTopOffset = -12.0;
  static const double badgeLeftOffset = 12.0;
  static const double badgeRadius = 20.0;
  static const double badgeRingSize = 14.0;
  static const double badgeRingWidth = 2.5;

  // 📅 HEADER DATE RANGE
  static const double headerDateTopGap = 8.0;
  static const double headerDateFontSize = 12.0;
  static const FontWeight headerDateWeight = FontWeight.w500;
  static const Color headerDateColor = Color(0xFF64748B); // DFColors.textSecondary
  
  // ===================================================================
  // ⏱ OVERVIEW TAB: PROJECT TIMELINE
  // ===================================================================
  static const double timelineTitleGap = 1.0; // Space below "Project Timeline" words
  static const double timelineContainerPadding = 24.0;
  static const double timelineContainerRadius = 10.0;
  
  // THE BAR
  static const double timelineBarHeight = 4.0;
  static const double timelineBarRadius = 4.0;
  static const double timelineBarBottomMargin = 20.0;
  
  // THE DOTS
  static const double timelineDotSize = 16.0;
  static const double timelineDotBorderWidth = 4.0;
  static const double timelineDotTopOffset = -6.0; // Adjust to center on bar
  
  // THE DATE LABELS (Start, Today, End)
  static const double timelineDateFontSize = 10.0;
  static const FontWeight timelineDateWeight = FontWeight.bold;
  static const double timelineDateLetterSpacing = 1.0;
  static const Color timelineTodayColor = Color(0xFF003E7E); // DFColors.primaryStitch

  // ===================================================================
  // 📊 OVERVIEW TAB: MATERIAL ESTIMATIONS
  // ===================================================================
  static const double matCardPadding = 24.0;
  static const double matCardPaddingVertical = 16.0; // Further reduced for ultra-slick look
  static const double matCardRadius = 12.0;
  static const double matCardBorderOpacity = 0.2;
  static const double matCardIndent = 20.0;           // Restored indent
  static const double matSubBulletSize = 4.0;        // New: Smaller dots for triple-style
  static const double matSubBulletVertGap = 4.0;     // New: Gap between the three dots
  
  static const double matTitleFontSize = 10.0;
  static const FontWeight matTitleWeight = FontWeight.bold;
  static const double matTitleLetterSpacing = 1.0;
  
  static const double matValueFontSize = 22.0;
  static const double matUnitFontSize = 12.0;
  static const double matValueTopGap = 4.0;
  
  static const double matStatusTopGap = 16.0;
  static const double matStatusRadius = 6.0;
  static const double matStatusFontSize = 10.0;
  static const double matStatusIconSize = 14.0;
  static const double matStatusCircleSize = 8.0;     // New: Status circle size
  static const double matStatusOutsideGap = 6.0;     // New: Gap below card for status

  // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
  // 👥 OVERVIEW TAB: ON-SITE TEAM
  // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
  static const double teamGridSpacing = 16.0;
  static const double teamCardAspectRatio = 2.5;
  static const double teamMemberAvatarSize = 40.0;
  static const double teamMemberAvatarRadius = 8.0;
  static const double teamMemberIndent = 20.0;           // New: To match materials
  static const double teamMemberRowGap = 12.0;           // New: Vertical space between rows
  
  static const double teamMemberNameFontSize = 14.0;
  static const FontWeight teamMemberNameWeight = FontWeight.bold;
  static const double teamMemberRoleFontSize = 11.0;
  static const double teamMemberInfoGap = 12.0;

  // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
  // 👷 OVERVIEW TAB: WORKFORCE & FINANCIALS
  // = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
   static const double utilCardPadding = 20.0;
   static const double utilIconSize = 24.0;
   static const double utilCardIndent = 20.0;           // New: To match materials
   static const double utilRowIconGap = 12.0;           // New: Space between icon and text
   static const double utilTitleFontSize = 10.0;
   static const FontWeight utilTitleWeight = FontWeight.bold;
   static const double utilCaptionFontSize = 11.0;
   static const double utilTitleTopGap = 8.0;           // Reduced for horizontal layout
   static const double utilCaptionTopGap = 4.0;
   
   // 📚 OVERVIEW TAB: FINANCIAL DOCS
   static const double financialCardIndent = 20.0;      // New: To match materials
   static const double financialCardHeight = 52.0;      // New: Low-profile height
  
  // 📑 TAB BAR SETTINGS
  static const double tabLeftPadding = 2.0;
  static const double tabRightPadding = 24.0;
  static const double screenTopPadding = 12.0;
  static const double tabItemVerticalPadding = 16.0;
  static const double tabItemHorizontalPadding = 16.0;
  static const double tabIndicatorWeight = 2.0;
}
