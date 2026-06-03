#include <Arduino.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <math.h>

// ---------------- BLE UUIDs ----------------
#define SERVICE_UUID "00001234-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "00005678-0000-1000-8000-00805f9b34fb"

// ---------------- OLED ----------------
U8G2_SSD1306_64X48_ER_F_HW_I2C u8g2(U8G2_R3, 16, 22, 21);

// ---------------- Layout ----------------
static const int OLED_W = 48;
static const int OLED_H = 64;
static const int HEADER_H = 8;

static const int MAP_X = 2;
static const int MAP_Y = 10;
static const int MAP_W = 44;
static const int MAP_H = 44;
static const int MAP_MIN_X = 2;
static const int MAP_MAX_X = 45;
static const int MAP_MIN_Y = 10;
static const int MAP_MAX_Y = 53;
static const int MAP_TEXT_Y = 62;

// ---------------- Turn Types ----------------
static const int TURN_STRAIGHT     = 0;
static const int TURN_LEFT         = 1;
static const int TURN_RIGHT        = 2;
static const int TURN_SLIGHT_LEFT  = 3;
static const int TURN_SLIGHT_RIGHT = 4;
static const int TURN_KEEP_LEFT    = 5;
static const int TURN_KEEP_RIGHT   = 6;
static const int TURN_ULEFT        = 7;
static const int TURN_URIGHT       = 8;
static const int TURN_ARRIVE       = 9;
static const int TURN_UNKNOWN      = 10;

// ---------------- Screen Modes ----------------
enum ScreenMode {
  MODE_HOME,
  MODE_PLACE,
  MODE_TIME,
  MODE_WEATHER,
  MODE_MAP
};

volatile ScreenMode currentMode = MODE_HOME;
volatile bool screenDirty = true;

// ---------------- Home animation ----------------
unsigned long lastHomeAnim = 0;
const unsigned long HOME_ANIM_INTERVAL = 220;
uint8_t homeAnimFrame = 0;

// ---------------- Point Type ----------------
struct Pt {
  uint8_t x;
  uint8_t y;
};

// ---------------- Mini-map state ----------------
bool mapMiniMode = false;

// Main route points
Pt routePts[48];
int routePtCount = 0;
int routeExpectedChunks = 0;
int routeReceivedChunks = 0;

// Background roads
Pt roadPts[160];
int roadPtCount = 0;
int roadExpectedChunks = 0;
int roadReceivedChunks = 0;

// Player
uint8_t playerX = 24;
uint8_t playerY = 44;
uint16_t playerHeading = 0;

// ---------------- Stored data ----------------
String homeTitle = "ARIS";
String homeStatus = "READY";
String homeMode = "HOME";

String receivedPlace = "UNKNOWN";
String receivedTime = "--:--:-- --";
String receivedDay = "04/30/26";

String receivedCity = "----";
String receivedTemp = "--";
String receivedHi = "--";
String receivedLo = "--";
String receivedCond = "--";

String mapTurn = "STRAIGHT";
String mapNextDist = "--";
String mapRoad = "--";
String mapRemain = "--";
String mapEta = "--";

// ---------------- Font helpers ----------------
void setHeaderFont() {
  u8g2.setFont(u8g2_font_4x6_tr);
}

void setBodyFont() {
  u8g2.setFont(u8g2_font_3x5im_tr);
}

void setHomeLogoFont() {
  u8g2.setFont(u8g2_font_ncenB14_tr);
}

void setMediumFont() {
  u8g2.setFont(u8g2_font_4x6_tr);
}

void setTimeFont() {
  u8g2.setFont(u8g2_font_5x7_tr);
}

// ---------------- Helpers ----------------
String cleanText(String s) {
  s.trim();
  s.replace("\r", "");
  s.replace("\n", " ");
  while (s.indexOf("  ") >= 0) s.replace("  ", " ");
  return s;
}

String upperClean(String s) {
  s = cleanText(s);
  s.toUpperCase();
  return s;
}

String getField(const String &s, int index, char sep) {
  int found = 0;
  int start = 0;

  for (int i = 0; i <= (int)s.length(); i++) {
    if (i == (int)s.length() || s.charAt(i) == sep) {
      if (found == index) return s.substring(start, i);
      found++;
      start = i + 1;
    }
  }
  return "";
}

int strW(const String &s) {
  return u8g2.getStrWidth(s.c_str());
}

void markDirty() {
  screenDirty = true;
}

int clampInt(int v, int lo, int hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

String shortCondition(String s) {
  String c = cleanText(s);
  c.toUpperCase();
  if (c.indexOf("THUNDER") >= 0) return "STORM";
  if (c.indexOf("DRIZZLE") >= 0) return "DRIZZLE";
  if (c.indexOf("RAIN") >= 0) return "RAIN";
  if (c.indexOf("OVERCAST") >= 0) return "OVERCAST";
  if (c.indexOf("CLOUD") >= 0) return "CLOUD";
  if (c.indexOf("CLEAR") >= 0) return "CLEAR";
  if (c.indexOf("SUN") >= 0) return "SUN";
  if (c.indexOf("FOG") >= 0) return "FOG";
  if (c.indexOf("MIST") >= 0) return "MIST";
  if (c.indexOf("WIND") >= 0) return "WIND";
  return c;
}

String abbreviateRoad(String s) {
  s = cleanText(s);
  s.toUpperCase();

  s.replace("BOULEVARD", "BLVD");
  s.replace("AVENUE", "AVE");
  s.replace("STREET", "ST");
  s.replace("ROAD", "RD");
  s.replace("DRIVE", "DR");
  s.replace("HIGHWAY", "HWY");
  s.replace("FREEWAY", "FWY");
  s.replace("PARKWAY", "PKWY");
  s.replace("LANE", "LN");
  s.replace("COURT", "CT");
  s.replace("CIRCLE", "CIR");
  s.replace("PLACE", "PL");
  s.replace("TERRACE", "TER");
  s.replace("MOUNT", "MT");
  s.replace("NORTH", "N");
  s.replace("SOUTH", "S");
  s.replace("EAST", "E");
  s.replace("WEST", "W");
  s.replace("CENTER", "CTR");
  s.replace("CORPORATE", "CORP");

  while (s.indexOf("  ") >= 0) s.replace("  ", " ");

  if (s.length() > 16) s = s.substring(0, 16);
  return s;
}

String compactDistance(String s) {
  s = cleanText(s);
  s.toUpperCase();
  s.replace(" ", "");
  return s;
}

String compactEta(String s) {
  s = cleanText(s);
  s.toUpperCase();
  s.replace("ETA", "");
  s.replace(" ", "");
  return s;
}

int getTurnType(String s) {
  s = upperClean(s);

  if (s.indexOf("ARRIVE") >= 0 || s.indexOf("DESTINATION") >= 0) return TURN_ARRIVE;

  if (s.indexOf("U-TURN") >= 0 || s.indexOf("UTURN") >= 0) {
    if (s.indexOf("RIGHT") >= 0) return TURN_URIGHT;
    if (s.indexOf("LEFT") >= 0) return TURN_ULEFT;
    return TURN_ULEFT;
  }

  if (s.indexOf("SLIGHT LEFT") >= 0) return TURN_SLIGHT_LEFT;
  if (s.indexOf("SLIGHT RIGHT") >= 0) return TURN_SLIGHT_RIGHT;
  if (s.indexOf("KEEP LEFT") >= 0) return TURN_KEEP_LEFT;
  if (s.indexOf("KEEP RIGHT") >= 0) return TURN_KEEP_RIGHT;
  if (s.indexOf("LEFT") >= 0) return TURN_LEFT;
  if (s.indexOf("RIGHT") >= 0) return TURN_RIGHT;
  if (s.indexOf("STRAIGHT") >= 0) return TURN_STRAIGHT;
  if (s.indexOf("CONTINUE") >= 0) return TURN_STRAIGHT;
  if (s.indexOf("HEAD") >= 0) return TURN_STRAIGHT;

  return TURN_UNKNOWN;
}

bool isHomeConnected() {
  String s = cleanText(homeStatus);
  s.toUpperCase();
  return (s == "CONNECTED");
}

int getWeatherIconType(String s) {
  s = upperClean(s);

  if (s.indexOf("THUNDER") >= 0 || s.indexOf("STORM") >= 0) return 5;
  if (s.indexOf("DRIZZLE") >= 0 || s.indexOf("RAIN") >= 0) return 4;
  if (s.indexOf("OVERCAST") >= 0 || s.indexOf("CLOUD") >= 0) return 2;
  if (s.indexOf("FOG") >= 0 || s.indexOf("MIST") >= 0) return 6;
  if (s.indexOf("WIND") >= 0) return 7;
  if (s.indexOf("CLEAR") >= 0 || s.indexOf("SUN") >= 0) return 1;

  return 3;
}

// ---------------- Drawing helpers ----------------
void drawHeaderBar(const String &label) {
  u8g2.drawBox(0, 0, OLED_W, HEADER_H);
  u8g2.setDrawColor(0);
  setHeaderFont();
  u8g2.drawStr(0, 6, label.c_str());
  u8g2.setDrawColor(1);
}

void drawCenteredText(int y, String text) {
  text = cleanText(text);
  int w = u8g2.getStrWidth(text.c_str());
  int x = (OLED_W - w) / 2;
  if (x < 0) x = 0;
  u8g2.drawStr(x, y, text.c_str());
}

int drawWrappedText(int x, int y, int maxWidth, int maxLines, String text, int lineStep) {
  text = cleanText(text);
  if (text.length() == 0) return y;

  int lineCount = 0;
  String line = "";
  int i = 0;

  while (i < text.length() && lineCount < maxLines) {
    while (i < text.length() && text.charAt(i) == ' ') i++;
    if (i >= text.length()) break;

    int nextSpace = text.indexOf(' ', i);
    String word;

    if (nextSpace == -1) {
      word = text.substring(i);
      i = text.length();
    } else {
      word = text.substring(i, nextSpace);
      i = nextSpace + 1;
    }

    if (line.length() == 0) {
      if (strW(word) <= maxWidth) {
        line = word;
      } else {
        String chunk = "";
        for (int k = 0; k < word.length(); k++) {
          String trial = chunk + word.charAt(k);
          if (strW(trial) <= maxWidth) {
            chunk = trial;
          } else {
            u8g2.drawStr(x, y + lineCount * lineStep, chunk.c_str());
            lineCount++;
            if (lineCount >= maxLines) return y + lineCount * lineStep;
            chunk = String(word.charAt(k));
          }
        }
        line = chunk;
      }
    } else {
      String trial = line + " " + word;
      if (strW(trial) <= maxWidth) {
        line = trial;
      } else {
        u8g2.drawStr(x, y + lineCount * lineStep, line.c_str());
        lineCount++;
        if (lineCount >= maxLines) return y + lineCount * lineStep;

        if (strW(word) <= maxWidth) {
          line = word;
        } else {
          String chunk = "";
          for (int k = 0; k < word.length(); k++) {
            String trial2 = chunk + word.charAt(k);
            if (strW(trial2) <= maxWidth) {
              chunk = trial2;
            } else {
              u8g2.drawStr(x, y + lineCount * lineStep, chunk.c_str());
              lineCount++;
              if (lineCount >= maxLines) return y + lineCount * lineStep;
              chunk = String(word.charAt(k));
            }
          }
          line = chunk;
        }
      }
    }
  }

  if (line.length() > 0 && lineCount < maxLines) {
    u8g2.drawStr(x, y + lineCount * lineStep, line.c_str());
    lineCount++;
  }

  return y + lineCount * lineStep;
}

void drawPlayerArrowAt(int x, int y, int headingDeg) {
  float rad = headingDeg * 3.14159f / 180.0f;

  int tipX = x + (int)(4.0f * sin(rad));
  int tipY = y - (int)(4.0f * cos(rad));

  int leftX = x + (int)(2.0f * sin(rad + 2.4f));
  int leftY = y - (int)(2.0f * cos(rad + 2.4f));

  int rightX = x + (int)(2.0f * sin(rad - 2.4f));
  int rightY = y - (int)(2.0f * cos(rad - 2.4f));

  u8g2.drawTriangle(tipX, tipY, leftX, leftY, rightX, rightY);
}

void drawThickLine(int x0, int y0, int x1, int y1) {
  u8g2.drawLine(x0, y0, x1, y1);
  u8g2.drawLine(x0 + 1, y0, x1 + 1, y1);
  u8g2.drawLine(x0, y0 + 1, x1, y1 + 1);
}

void drawNavArrow(int t) {
  int cx = 24;

  switch (t) {
    case TURN_STRAIGHT:
      u8g2.drawBox(cx - 2, 24, 5, 14);
      u8g2.drawTriangle(cx, 12, cx - 8, 24, cx + 8, 24);
      break;

    case TURN_RIGHT:
      u8g2.drawBox(cx - 10, 26, 5, 14);
      u8g2.drawBox(cx - 10, 21, 16, 5);
      u8g2.drawTriangle(cx + 13, 23, cx + 5, 16, cx + 5, 30);
      break;

    case TURN_LEFT:
      u8g2.drawBox(cx + 5, 26, 5, 14);
      u8g2.drawBox(cx - 6, 21, 16, 5);
      u8g2.drawTriangle(cx - 13, 23, cx - 5, 16, cx - 5, 30);
      break;

    case TURN_SLIGHT_RIGHT:
      drawThickLine(cx - 4, 38, cx - 1, 31);
      drawThickLine(cx - 1, 31, cx + 6, 23);
      u8g2.drawTriangle(cx + 12, 18, cx + 5, 19, cx + 9, 26);
      break;

    case TURN_SLIGHT_LEFT:
      drawThickLine(cx + 4, 38, cx + 1, 31);
      drawThickLine(cx + 1, 31, cx - 6, 23);
      u8g2.drawTriangle(cx - 12, 18, cx - 5, 19, cx - 9, 26);
      break;

    case TURN_KEEP_RIGHT:
      u8g2.drawBox(cx - 4, 28, 4, 10);
      drawThickLine(cx - 2, 28, cx + 5, 22);
      u8g2.drawTriangle(cx + 10, 18, cx + 4, 19, cx + 8, 24);
      break;

    case TURN_KEEP_LEFT:
      u8g2.drawBox(cx + 1, 28, 4, 10);
      drawThickLine(cx + 3, 28, cx - 4, 22);
      u8g2.drawTriangle(cx - 10, 18, cx - 4, 19, cx - 8, 24);
      break;

    case TURN_ULEFT:
      u8g2.drawBox(cx + 6, 25, 4, 14);
      drawThickLine(cx + 8, 25, cx + 2, 19);
      u8g2.drawBox(cx - 5, 17, 4, 10);
      u8g2.drawLine(cx + 2, 19, cx - 1, 19);
      u8g2.drawLine(cx + 2, 20, cx - 1, 20);
      u8g2.drawTriangle(cx - 11, 22, cx - 3, 17, cx - 3, 27);
      break;

    case TURN_URIGHT:
      u8g2.drawBox(cx - 10, 25, 4, 14);
      drawThickLine(cx - 8, 25, cx - 2, 19);
      u8g2.drawBox(cx + 1, 17, 4, 10);
      u8g2.drawLine(cx - 2, 19, cx + 1, 19);
      u8g2.drawLine(cx - 2, 20, cx + 1, 20);
      u8g2.drawTriangle(cx + 11, 22, cx + 3, 17, cx + 3, 27);
      break;

    case TURN_ARRIVE:
      u8g2.drawLine(cx - 6, 14, cx - 6, 38);
      u8g2.drawTriangle(cx - 5, 14, cx + 9, 18, cx - 5, 22);
      u8g2.drawLine(cx - 10, 38, cx - 2, 38);
      break;

    case TURN_UNKNOWN:
    default:
      u8g2.drawBox(cx - 2, 24, 5, 14);
      u8g2.drawTriangle(cx, 12, cx - 8, 24, cx + 8, 24);
      break;
  }
}

// ---------------- Weather icons ----------------
void drawSunIcon(int x, int y) {
  u8g2.drawCircle(x, y, 4);
  u8g2.drawLine(x, y - 7, x, y - 5);
  u8g2.drawLine(x, y + 5, x, y + 7);
  u8g2.drawLine(x - 7, y, x - 5, y);
  u8g2.drawLine(x + 5, y, x + 7, y);
  u8g2.drawLine(x - 5, y - 5, x - 4, y - 4);
  u8g2.drawLine(x + 5, y - 5, x + 4, y - 4);
  u8g2.drawLine(x - 5, y + 5, x - 4, y + 4);
  u8g2.drawLine(x + 5, y + 5, x + 4, y + 4);
}

void drawCloudIcon(int x, int y) {
  u8g2.drawDisc(x - 5, y + 1, 3);
  u8g2.drawDisc(x, y - 1, 4);
  u8g2.drawDisc(x + 5, y + 1, 3);
  u8g2.drawBox(x - 8, y + 1, 16, 4);
}

void drawRainIcon(int x, int y) {
  drawCloudIcon(x, y);
  u8g2.drawLine(x - 5, y + 7, x - 6, y + 10);
  u8g2.drawLine(x,     y + 7, x - 1, y + 10);
  u8g2.drawLine(x + 5, y + 7, x + 4, y + 10);
}

void drawStormIcon(int x, int y) {
  drawCloudIcon(x, y);
  u8g2.drawLine(x + 1, y + 6, x - 2, y + 10);
  u8g2.drawLine(x - 2, y + 10, x + 1, y + 10);
  u8g2.drawLine(x + 1, y + 10, x - 1, y + 14);
}

void drawFogIcon(int x, int y) {
  drawCloudIcon(x, y - 2);
  u8g2.drawLine(x - 8, y + 7, x + 8, y + 7);
  u8g2.drawLine(x - 6, y + 10, x + 6, y + 10);
  u8g2.drawLine(x - 8, y + 13, x + 8, y + 13);
}

void drawWindIcon(int x, int y) {
  u8g2.drawLine(x - 8, y - 2, x + 6, y - 2);
  u8g2.drawPixel(x + 7, y - 3);
  u8g2.drawPixel(x + 8, y - 4);

  u8g2.drawLine(x - 6, y + 2, x + 8, y + 2);
  u8g2.drawPixel(x + 9, y + 1);

  u8g2.drawLine(x - 8, y + 6, x + 4, y + 6);
  u8g2.drawPixel(x + 5, y + 5);
}

void drawPartlyCloudyIcon(int x, int y) {
  drawSunIcon(x - 4, y - 1);
  drawCloudIcon(x + 2, y + 2);
}

void drawWeatherIconByCondition(int x, int y, String cond) {
  int t = getWeatherIconType(cond);

  switch (t) {
    case 1: drawSunIcon(x, y); break;
    case 2: drawCloudIcon(x, y); break;
    case 4: drawRainIcon(x, y); break;
    case 5: drawStormIcon(x, y); break;
    case 6: drawFogIcon(x, y); break;
    case 7: drawWindIcon(x, y); break;
    case 3:
    default:
      drawPartlyCloudyIcon(x, y); break;
  }
}

// ---------------- Home art helpers ----------------
void drawSparkle(int cx, int cy, uint8_t frame) {
  u8g2.drawPixel(cx, cy);

  if (frame == 0 || frame == 2) {
    u8g2.drawLine(cx - 3, cy, cx + 3, cy);
    u8g2.drawLine(cx, cy - 3, cx, cy + 3);
  } else {
    u8g2.drawLine(cx - 2, cy - 2, cx + 2, cy + 2);
    u8g2.drawLine(cx - 2, cy + 2, cx + 2, cy - 2);
  }

  if (frame == 2) {
    u8g2.drawPixel(cx - 4, cy);
    u8g2.drawPixel(cx + 4, cy);
    u8g2.drawPixel(cx, cy - 4);
    u8g2.drawPixel(cx, cy + 4);
  }
}

void drawBulb(int cx, int cy, uint8_t frame) {
  u8g2.drawDisc(cx, cy, 2);
  u8g2.drawBox(cx - 1, cy + 2, 3, 2);
  u8g2.drawPixel(cx, cy);

  if (frame == 0 || frame == 2) {
    u8g2.drawPixel(cx - 4, cy);
    u8g2.drawPixel(cx + 4, cy);
    u8g2.drawPixel(cx, cy - 4);
  }

  if (frame == 1 || frame == 3) {
    u8g2.drawPixel(cx - 3, cy - 3);
    u8g2.drawPixel(cx + 3, cy - 3);
    u8g2.drawPixel(cx, cy - 5);
  }

  if (frame == 2) {
    u8g2.drawCircle(cx, cy, 3);
  }
}

void drawDisconnectedIDotMask(int x, int baselineY) {
  u8g2.setDrawColor(0);
  u8g2.drawBox(x + 24, baselineY - 15, 7, 6);
  u8g2.setDrawColor(1);
}

// ---------------- Screens ----------------
void drawHomeScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("HOME");

  bool connected = isHomeConnected();
  uint8_t f = homeAnimFrame & 0x03;

  setHomeLogoFont();

  String logo = "Aris";
  int logoW = strW(logo);
  int x = (OLED_W - logoW) / 2;
  if (x < 0) x = 0;
  int baselineY = 35;

  u8g2.drawStr(x, baselineY, logo.c_str());
  drawDisconnectedIDotMask(x, baselineY);

  if (connected) {
    drawBulb(x + 25, baselineY - 15, f);
  }

  u8g2.drawLine(9, 45, 15, 42);
  u8g2.drawLine(15, 42, 24, 41);
  u8g2.drawLine(24, 41, 33, 42);
  u8g2.drawLine(33, 42, 39, 45);

  u8g2.sendBuffer();
}

void drawPlaceScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("PLACE");
  setBodyFont();
  drawWrappedText(0, 14, OLED_W, 8, receivedPlace, 6);
  u8g2.sendBuffer();
}

void drawTimeScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("TIME");

  String timeText = cleanText(receivedTime);  // "12:45:09 AM"
  String dateText = cleanText(receivedDay);   // "04/30/26"

  // Split time and AM/PM
  String mainTime = timeText;
  String ampm = "";

  int lastSpace = timeText.lastIndexOf(' ');
  if (lastSpace > 0) {
    mainTime = timeText.substring(0, lastSpace);   // "12:45:09"
    ampm = timeText.substring(lastSpace + 1);      // "AM"
  }

  // LEFT-aligned position
  int timeX = 2;
  int timeY = 26;

  // Draw main time
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(timeX, timeY, mainTime.c_str());

  // Draw AM/PM tight + slightly raised
  if (ampm.length() > 0) {
    int mainW = u8g2.getStrWidth(mainTime.c_str());
    u8g2.setFont(u8g2_font_3x5im_tr);
    u8g2.drawStr(timeX + mainW + 1, timeY - 3, ampm.c_str());
  }

  // Draw DATE below (NOT weekday)
  u8g2.setFont(u8g2_font_4x6_tr);
  u8g2.drawStr(2, 40, dateText.c_str());

  u8g2.sendBuffer();
}

void drawWeatherScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("WEA");

  String cond = shortCondition(receivedCond);
  String tempLine = receivedTemp + "F";
  String hiLoLine = "H" + receivedHi + " L" + receivedLo;

  drawWeatherIconByCondition(24, 18, cond);

  setMediumFont();
  drawCenteredText(34, tempLine);

  setBodyFont();
  drawCenteredText(44, hiLoLine);

  String condShort = cond;
  if (condShort.length() > 12) condShort = condShort.substring(0, 12);
  drawCenteredText(54, condShort);

  u8g2.sendBuffer();
}

void drawMapScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("NAV");

  int turnType = getTurnType(mapTurn);
  drawNavArrow(turnType);

  setBodyFont();

  String roadText = abbreviateRoad(mapRoad);
  if (roadText.length() == 0 || roadText == "--") roadText = "UNKNOWN RD";

  String distText = compactDistance(mapNextDist);
  if (distText.length() == 0 || distText == "--") distText = "--";

  String etaText = compactEta(mapEta);
  if (etaText.length() == 0 || etaText == "--") etaText = "--";

  drawCenteredText(48, roadText);
  drawCenteredText(56, distText + " ETA:" + etaText);

  u8g2.sendBuffer();
}

void drawMiniMapScreen() {
  u8g2.clearBuffer();
  drawHeaderBar("MINI");

  u8g2.drawFrame(MAP_X, MAP_Y, MAP_W, MAP_H);

  for (int i = 0; i < roadPtCount - 1; i++) {
    if ((roadPts[i].x == 255 && roadPts[i].y == 255) ||
        (roadPts[i + 1].x == 255 && roadPts[i + 1].y == 255)) {
      continue;
    }
    u8g2.drawLine(roadPts[i].x, roadPts[i].y, roadPts[i + 1].x, roadPts[i + 1].y);
  }

  for (int i = 0; i < routePtCount - 1; i++) {
    if ((routePts[i].x == 255 && routePts[i].y == 255) ||
        (routePts[i + 1].x == 255 && routePts[i + 1].y == 255)) {
      continue;
    }

    u8g2.drawLine(routePts[i].x, routePts[i].y, routePts[i + 1].x, routePts[i + 1].y);

    if (routePts[i].x + 1 <= MAP_MAX_X && routePts[i + 1].x + 1 <= MAP_MAX_X) {
      u8g2.drawLine(routePts[i].x + 1, routePts[i].y, routePts[i + 1].x + 1, routePts[i + 1].y);
    }
  }

  drawPlayerArrowAt(playerX, playerY, playerHeading);

  setBodyFont();
  String dist = compactDistance(mapNextDist);
  int tw = u8g2.getStrWidth(dist.c_str());
  int tx = (OLED_W - tw) / 2;
  u8g2.drawStr(tx, MAP_TEXT_Y, dist.c_str());

  u8g2.sendBuffer();
}

void updateOLED() {
  switch (currentMode) {
    case MODE_HOME:
      drawHomeScreen();
      break;
    case MODE_PLACE:
      drawPlaceScreen();
      break;
    case MODE_TIME:
      drawTimeScreen();
      break;
    case MODE_WEATHER:
      drawWeatherScreen();
      break;
    case MODE_MAP:
      if (mapMiniMode) drawMiniMapScreen();
      else drawMapScreen();
      break;
  }
}

// ---------------- BLE Callback ----------------
class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String msg = String(pCharacteristic->getValue().c_str());
    msg = cleanText(msg);

    if (msg.length() == 0) return;
    Serial.print("RX: ");
    Serial.println(msg);
    if (msg.startsWith("MAPVIEW:")) {
      String v = msg.substring(8);
      v.toUpperCase();

      if (v == "MINI") mapMiniMode = true;
      else if (v == "TEXT") mapMiniMode = false;

      currentMode = MODE_MAP;
      markDirty();
      return;
    }

    if (msg.startsWith("PLY:")) {
      String payload = msg.substring(4);

      int px = getField(payload, 0, ',').toInt();
      int py = getField(payload, 1, ',').toInt();
      int hd = getField(payload, 2, ',').toInt();

      px = clampInt(px, MAP_MIN_X, MAP_MAX_X);
      py = clampInt(py, MAP_MIN_Y, MAP_MAX_Y);

      while (hd < 0) hd += 360;
      while (hd >= 360) hd -= 360;

      playerX = (uint8_t)px;
      playerY = (uint8_t)py;
      playerHeading = (uint16_t)hd;

      currentMode = MODE_MAP;
      mapMiniMode = true;
      markDirty();
      return;
    }

    if (msg.startsWith("RD:")) {
      String payload = msg.substring(3);

      int firstComma = payload.indexOf(',');
      int secondComma = payload.indexOf(',', firstComma + 1);
      if (firstComma < 0 || secondComma < 0) return;

      int chunkIndex = payload.substring(0, firstComma).toInt();
      int totalChunks = payload.substring(firstComma + 1, secondComma).toInt();
      String ptsPart = payload.substring(secondComma + 1);

      if (chunkIndex == 0) {
        roadPtCount = 0;
        roadReceivedChunks = 0;
        roadExpectedChunks = totalChunks;
      }

      int start = 0;
      while (start < ptsPart.length() && roadPtCount < 160) {
        int comma1 = ptsPart.indexOf(',', start);
        if (comma1 < 0) break;
        int comma2 = ptsPart.indexOf(',', comma1 + 1);

        String xs = ptsPart.substring(start, comma1);
        String ys;

        if (comma2 < 0) {
          ys = ptsPart.substring(comma1 + 1);
          start = ptsPart.length();
        } else {
          ys = ptsPart.substring(comma1 + 1, comma2);
          start = comma2 + 1;
        }

        int rx = xs.toInt();
        int ry = ys.toInt();

        if (rx == -1 && ry == -1) {
          roadPts[roadPtCount].x = 255;
          roadPts[roadPtCount].y = 255;
          roadPtCount++;
          continue;
        }

        rx = clampInt(rx, MAP_MIN_X, MAP_MAX_X);
        ry = clampInt(ry, MAP_MIN_Y, MAP_MAX_Y);

        roadPts[roadPtCount].x = (uint8_t)rx;
        roadPts[roadPtCount].y = (uint8_t)ry;
        roadPtCount++;
      }

      roadReceivedChunks++;
      currentMode = MODE_MAP;
      mapMiniMode = true;
      markDirty();
      return;
    }

    if (msg.startsWith("RTE:")) {
      String payload = msg.substring(4);

      int firstComma = payload.indexOf(',');
      int secondComma = payload.indexOf(',', firstComma + 1);
      if (firstComma < 0 || secondComma < 0) return;

      int chunkIndex = payload.substring(0, firstComma).toInt();
      int totalChunks = payload.substring(firstComma + 1, secondComma).toInt();
      String ptsPart = payload.substring(secondComma + 1);

      if (chunkIndex == 0) {
        routePtCount = 0;
        routeReceivedChunks = 0;
        routeExpectedChunks = totalChunks;
      }

      int start = 0;
      while (start < ptsPart.length() && routePtCount < 48) {
        int comma1 = ptsPart.indexOf(',', start);
        if (comma1 < 0) break;
        int comma2 = ptsPart.indexOf(',', comma1 + 1);

        String xs = ptsPart.substring(start, comma1);
        String ys;

        if (comma2 < 0) {
          ys = ptsPart.substring(comma1 + 1);
          start = ptsPart.length();
        } else {
          ys = ptsPart.substring(comma1 + 1, comma2);
          start = comma2 + 1;
        }

        int rx = xs.toInt();
        int ry = ys.toInt();

        if (rx == -1 && ry == -1) {
          routePts[routePtCount].x = 255;
          routePts[routePtCount].y = 255;
          routePtCount++;
          continue;
        }

        rx = clampInt(rx, MAP_MIN_X, MAP_MAX_X);
        ry = clampInt(ry, MAP_MIN_Y, MAP_MAX_Y);

        routePts[routePtCount].x = (uint8_t)rx;
        routePts[routePtCount].y = (uint8_t)ry;
        routePtCount++;
      }

      routeReceivedChunks++;
      currentMode = MODE_MAP;
      mapMiniMode = true;
      markDirty();
      return;
    }

    if (msg.startsWith("MODE:")) {
      String m = msg.substring(5);
      m.toUpperCase();

      if (m == "HOME") currentMode = MODE_HOME;
      else if (m == "PLACE") currentMode = MODE_PLACE;
      else if (m == "TIME") currentMode = MODE_TIME;
      else if (m == "WEATHER") currentMode = MODE_WEATHER;
      else if (m == "MAP") currentMode = MODE_MAP;

      markDirty();
      return;
    }

    if (msg.startsWith("HOME:")) {
      String payload = msg.substring(5);
      homeTitle = cleanText(getField(payload, 0, '|'));
      homeStatus = cleanText(getField(payload, 1, '|'));
      homeMode = cleanText(getField(payload, 2, '|'));

      if (homeTitle.length() == 0) homeTitle = "ARIS";
      if (homeStatus.length() == 0) homeStatus = "READY";
      if (homeMode.length() == 0) homeMode = "HOME";

      currentMode = MODE_HOME;
      homeAnimFrame = 0;
      lastHomeAnim = millis();
      markDirty();
      return;
    }

    if (msg.startsWith("PLACE:")) {
      receivedPlace = cleanText(msg.substring(6));
      if (receivedPlace.length() == 0) receivedPlace = "UNKNOWN";

      currentMode = MODE_PLACE;
      markDirty();
      return;
    }

    if (msg.startsWith("TIME:")) {
      String payload = msg.substring(5);
      receivedTime = cleanText(getField(payload, 0, '|'));
      receivedDay = cleanText(getField(payload, 1, '|'));

      if (receivedTime.length() == 0) receivedTime = "--:--:-- --";
      if (receivedDay.length() == 0) receivedDay = "00/00/00";

      currentMode = MODE_TIME;
      markDirty();
      return;
    }

    if (msg.startsWith("WEATHER:")) {
      String payload = msg.substring(8);

      receivedCity = cleanText(getField(payload, 0, '|'));
      receivedTemp = cleanText(getField(payload, 1, '|'));

      String hiField = cleanText(getField(payload, 2, '|'));
      String loField = cleanText(getField(payload, 3, '|'));
      receivedCond = cleanText(getField(payload, 4, '|'));

      if (hiField.startsWith("H")) receivedHi = hiField.substring(1);
      else receivedHi = hiField;

      if (loField.startsWith("L")) receivedLo = loField.substring(1);
      else receivedLo = loField;

      if (receivedCity.length() == 0) receivedCity = "----";
      if (receivedTemp.length() == 0) receivedTemp = "--";
      if (receivedHi.length() == 0) receivedHi = "--";
      if (receivedLo.length() == 0) receivedLo = "--";
      if (receivedCond.length() == 0) receivedCond = "--";

      currentMode = MODE_WEATHER;
      markDirty();
      return;
    }

    if (msg.startsWith("MAP:")) {
      String payload = msg.substring(4);

      mapTurn = cleanText(getField(payload, 0, '|'));
      mapNextDist = cleanText(getField(payload, 1, '|'));
      mapRoad = cleanText(getField(payload, 2, '|'));
      mapRemain = cleanText(getField(payload, 3, '|'));
      mapEta = cleanText(getField(payload, 4, '|'));

      if (mapTurn.length() == 0) mapTurn = "STRAIGHT";
      if (mapNextDist.length() == 0) mapNextDist = "--";
      if (mapRoad.length() == 0) mapRoad = "--";
      if (mapRemain.length() == 0) mapRemain = "--";
      if (mapEta.length() == 0) mapEta = "--";

      currentMode = MODE_MAP;
      markDirty();
      return;
    }
  }
};

void resetOLED() {
  pinMode(16, OUTPUT);
  digitalWrite(16, HIGH);
  delay(10);
  digitalWrite(16, LOW);
  delay(20);
  digitalWrite(16, HIGH);
  delay(50);
}
// ---------------- Setup ----------------
void setup() {
  Serial.begin(115200);
  delay(200);

  Wire.begin(21, 22);
  resetOLED();
  u8g2.begin();
  
  // mirror for your optics
  u8g2.sendF("c", 0xA1);
  u8g2.sendF("c", 0xC0);
  
  u8g2.clearBuffer();
  drawHeaderBar("BOOT");
  setBodyFont();
  drawWrappedText(0, 14, OLED_W, 6, "ARIS BLE READY", 6);
  u8g2.sendBuffer();
  BLEDevice::init("ARIS-ESP32");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  lastHomeAnim = millis();
  updateOLED();
}

// ---------------- Loop ----------------
void loop() {
  unsigned long now = millis();

  if (currentMode == MODE_HOME) {
    if (now - lastHomeAnim >= HOME_ANIM_INTERVAL) {
      lastHomeAnim = now;
      homeAnimFrame = (homeAnimFrame + 1) & 0x03;
      markDirty();
    }
  }

  if (screenDirty) {
    screenDirty = false;
    updateOLED();
  }

  delay(5);
}
