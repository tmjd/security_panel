#include <Arduino.h>
#include <LiquidCrystal.h>
#include <Keypad.h>
#include "hs_general.h"

#define SERIAL_MONITOR

const int LOOP_DELAY = 10;

//====== For LCD
// lcd(rs, en, d0, d1, d2, d3)
LiquidCrystal lcd(16,15,14,13,12,11);
const int LCD_BL_PIN = 10;
const int LCD_BL_ON = HIGH;
const int LCD_BL_OFF = LOW;
const int LCD_LINE_LEN = 21;
char lcdLines[4][LCD_LINE_LEN];

void ClearLine(int line)
{
  if( line < 4 )
  {
    memset(lcdLines[line], ' ', LCD_LINE_LEN);
    lcdLines[line][LCD_LINE_LEN-1] = '\0';
  }
}

void SetLcdLine(int line, const char * string, int len)
{
  ClearLine(line);
  memcpy(lcdLines[line], string, min(len,LCD_LINE_LEN-1));
};

void UpdateDisplay()
{
  lcd.setCursor(0,0);
  lcd.print(lcdLines[0]);
  lcd.setCursor(0,1);
  lcd.print(lcdLines[1]);
  lcd.setCursor(0,2);
  lcd.print(lcdLines[2]);
  lcd.setCursor(0,3);
  lcd.print(lcdLines[3]);
};

//====== For Motion detection
const byte MTN_PIN = 2;
const int MTN_ACTIVE = LOW;
const int MTN_NONE = HIGH;
const char MTN_NAME[] = "Main Panel Mtn";

void CheckMotion()
{
  const int mtn_level = digitalRead(MTN_PIN);

  if (MTN_ACTIVE  == mtn_level)
  {
    TurnLcdBlOn();
  }
  
#if !defined SERIAL_MONITOR
  if(MTN_ACTIVE == mtn_level)
  {
    SEND_SERIAL(Serial, TYPE_MOTION, MTN_NAME, STATE_TRIPPED, NULL);
  }
  else
  {
    SEND_SERIAL(Serial, TYPE_MOTION, MTN_NAME, STATE_CLEARED, NULL);
  }
#endif
};

//====== For Buzzer
const byte BUZZ_PIN = 6;
byte buzzDuty = 127;
int buzzMsOn;
int buzzMsPer;
int buzzPerCnt;
void UpdateBuzzer(int ms_on, int ms_period)
{
  if((ms_on != buzzMsOn) || (ms_period != buzzMsPer))
  {
    buzzMsOn = ms_on;
    buzzMsPer = ms_period;
    // Reset the counts so restart the buzz state
    buzzPerCnt = 0;
  }
};

void BuzzerUpdate()
{
  // If buzz period is less than 0 then the buzzer is
  // disabled.
  if(buzzMsPer < 0)
  {
    analogWrite(BUZZ_PIN, 0);
  }
  else
  {
    if(buzzPerCnt == 0)
    {
      analogWrite(BUZZ_PIN, buzzDuty);
    }
    if(buzzPerCnt > (buzzMsOn/LOOP_DELAY))
    {
      analogWrite(BUZZ_PIN, 0);
    }
    if(buzzPerCnt >= (buzzMsPer/LOOP_DELAY))
    {
      buzzPerCnt = 0;
    }
    else
    {
      buzzPerCnt++;
    }
  }
};

//======
enum eSTATUS
{
  eSTATUS_ALARMED,
  eSTATUS_DELAYED_ALARM,
  eSTATUS_ARMED,
  eSTATUS_STANDBY,
  eSTATUS_ARMING
};
eSTATUS curStatus = eSTATUS_STANDBY;

const unsigned long BL_OFF_DELAY = 10*1000;
unsigned long lcdBlOffTime = 0;
// Do a local check every half second
const unsigned long LOCAL_CHECK_DELAY = (.5*1000);
unsigned long nextLocalCheck = 0;
const unsigned long KEYPAD_RESET_DELAY = 5*1000;
unsigned long resetInputTime = 0;


//====== For Keypad
const byte ROWS = 4;
const byte COLS = 3;
char keys[ROWS][COLS] = {
  {'1','2','3'},
  {'4','5','6'},
  {'7','8','9'},
  {'*','0','#'}
};
byte rowPins[ROWS] = {9, 5, 7, 8}; //connect to the row pinouts of the keypad
byte colPins[COLS] = {12, 11, 13}; //connect to the column pinouts of the keypad
Keypad keypad = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );
const int INPUT_SIZE = 21;
char keypadInput[INPUT_SIZE];
int keypadInputLen = 0;
const char SENT_STRING[] = "Sent Command";
const char CLEARED[] = "Cleared";

void AddInputCharacter(char newChar)
{
  if((newChar == '*') || (keypadInputLen == (INPUT_SIZE-1)))
  {
    if(0 == keypadInputLen)
    {
      // Do nothing the input is nothing so far, this should allow
      // turning the LCD on but not wiping out the 4th row.
    }
    else
    {
      ClearInputString();
      SetLcdLine(3, CLEARED, strlen(CLEARED));
    }
  }
  else if (newChar == '#')
  {
    keypadInput[keypadInputLen] = '\0';
    SEND_SERIAL(Serial, TYPE_INPUT, USER_INPUT, keypadInput, NULL);
    ClearInputString();
    SetLcdLine(3, SENT_STRING, strlen(SENT_STRING));
  }
  else
  {
    resetInputTime = millis()+KEYPAD_RESET_DELAY;
    keypadInput[keypadInputLen] = newChar;
    keypadInputLen++;
  }
};

void ReadKeypadInput()
{
  keypad.getKeys();
  char key = keypad.getKey();
  if( key != NO_KEY )
  {
    TurnLcdBlOn();
    AddInputCharacter(key);
  }
  
  if(keypadInputLen > 0)
  {
    SetLcdLine(3, keypadInput, keypadInputLen);
  }
};

void ClearInputString()
{
  memset(keypadInput, ' ', INPUT_SIZE);
  keypadInput[INPUT_SIZE-1] = '\0';
  keypadInputLen = 0;
};

void TurnLcdBlOn()
{
  digitalWrite(LCD_BL_PIN, LCD_BL_ON);
  lcdBlOffTime = millis()+BL_OFF_DELAY;
};

SerialInput incomingData;
int lineToWrite = 0;
void ReadSerial()
{
  int ipos = -1;
  READ_SERIAL(Serial, incomingData);

  FIND_END(incomingData, ipos);
  if(-1 != ipos)
  {
    //Change the newline character to a null terminator to
    // set the end of the line read in.
    incomingData.data[ipos] = '\0';
#if !defined SERIAL_MONITOR
    ProcessMessage(incomingData.data, ipos);
#else
    SetLcdLine(0, incomingData.data, ipos);
#endif

    //Clear out the data, plus 1 is to include clearing the new line
    CLEAR_DATA(incomingData, ipos+1);
  }
  
  if(incomingData.dataLen >= MAX_SERIAL_IN)
  {
    CLEAR_DATA(incomingData,MAX_SERIAL_IN);
  }
};

void ProcessMessage(char * msgStr, int len)
{
  Message msg;
  if(true == ParseMessage(msgStr, msg))
  {
    if(0 == strncmp(msg.source, "0", MSG_INT_SIZE))
    {
      if(0 == strncmp(msg.msgType, TYPE_LINE, MSG_INT_SIZE))
      {
        if(0 == strncmp(msg.name, "Line1", NAME_SIZE))
        {
          SetLcdLine(0, msg.info, strlen(msg.info));
        }
        else if(0 == strncmp(msg.name, "Line2", NAME_SIZE))
        {
          SetLcdLine(1, msg.info, strlen(msg.info));
        }
        else if(0 == strncmp(msg.name, "Line3", NAME_SIZE))
        {
          SetLcdLine(2, msg.info, strlen(msg.info));
        }
        else if(0 == strncmp(msg.name, "Line4", NAME_SIZE))
        {
          SetLcdLine(3, msg.info, strlen(msg.info));
        }
      }
      else if(0 == strncmp(msg.msgType, TYPE_STATUS, MSG_INT_SIZE))
      {
        if(0 == strncmp(msg.info, STATUS_ALARMED, NAME_SIZE))
        {
          // ALARM DETECTED
          curStatus = eSTATUS_ALARMED;
        }
        else if(0 == strncmp(msg.info, STATUS_DELAY_ALARM, NAME_SIZE))
        {
          // delayed alarm
          curStatus = eSTATUS_DELAYED_ALARM;
        }
        else if(0 == strncmp(msg.info, STATUS_ARMED, NAME_SIZE))
        {
          // armed
          curStatus = eSTATUS_ARMED;
        }
        else if(0 == strncmp(msg.info, STATUS_STANDBY, NAME_SIZE))
        {
          // standby
          curStatus = eSTATUS_STANDBY;
        }
          else if(0 == strncmp(msg.info, STATUS_ARMING, NAME_SIZE))
        {
          // arming
          curStatus = eSTATUS_ARMING;
        }
        else
        {
          curStatus = eSTATUS_ALARMED;
        }
      }
    }
    else
    {
      // Do not care about messages from anyone but the source 0
    }
  }
  else
  {
    // message parsing was unsuccessful
  }
};

// The setup() method runs once, when the sketch starts
void setup()   
{
  SRC_ID = 2;
  Serial.begin(9600);

  lcd.begin(20,4);
  lcd.setCursor(0,0);
  lcd.print("Hello World");
  
  pinMode(MTN_PIN, INPUT);
  pinMode(BUZZ_PIN, OUTPUT);
  
  pinMode(LCD_BL_PIN, OUTPUT);
  digitalWrite(LCD_BL_PIN, LCD_BL_ON);
  
  buzzMsOn = 0;
  buzzMsPer = -1;
  buzzPerCnt = 0;
  
  incomingData.dataLen = 0;
};

// the loop() method runs over and over again,
// as long as the Arduino has power
void loop()
{
  if( nextLocalCheck < millis() )
  {
    nextLocalCheck = millis()+LOCAL_CHECK_DELAY;
    CheckMotion();
  }
  
  if( millis() > lcdBlOffTime )
  {
    digitalWrite(LCD_BL_PIN, LCD_BL_OFF);
    ClearInputString();
  }

  if( millis() > resetInputTime )
  {
    ClearInputString();
  }
  
  ReadSerial();
  
  //ReadKeypadInput();
  
  UpdateDisplay();
  
  switch(curStatus)
  {
    case eSTATUS_ALARMED:
      TurnLcdBlOn();
      UpdateBuzzer(500,1000);
      break;
    case eSTATUS_DELAYED_ALARM:
      TurnLcdBlOn();
      UpdateBuzzer(50, 1000);
      break;
    case eSTATUS_ARMED:
      UpdateBuzzer(0, -1);
      break;
    case eSTATUS_STANDBY:
      UpdateBuzzer(0, -1);
      break;
    case eSTATUS_ARMING:
      UpdateBuzzer(50,1000);
      break;
    default:
      break;
  };

  BuzzerUpdate();
  
  delay(LOOP_DELAY);
};

/*
    switch(key)
    {
      case '0':
        ledReg = 0;
        break;
      case '1':
        ledReg ^= 1 << 2;
        break;
      case '2':
        ledReg ^= 1 << 3;
        break;
      case '3':
        ledReg ^= 1 << 4;
        break;
      case '4':
        ledReg ^= 1 << 5;
        break;
      case '5':
        ledReg ^= 1 << 6;
        break;
//      case '7':
//        buzzDuty += 10;
//        break;
//      case '8':
//        buzzDuty = 0;
//        break;
//      case '9':
//        buzzDuty -= 10;
//        break;
      case '*':
        if (lcdBlOn == HIGH)
          lcdBlOn = LOW;
        else
          lcdBlOn = HIGH;
        break;
      default:
        break;
    }
    
//    digitalWrite(LCD_BL_PIN, LCD_BL_ON);
//    analogWrite(BUZZ_PIN, buzzDuty);
    
//    setShiftReg(ledReg);
*/

//====== For shift register (LEDs)
const byte LATCH_PIN = 4;
const byte RESET_PIN = 11;
const byte SHFT_CLK_PIN = 13;
const byte SER_IN_PIN = 12;
const byte SHIFT_PINS = 4;
byte ShiftPins[] = { LATCH_PIN, RESET_PIN, SHFT_CLK_PIN, SER_IN_PIN };
byte ledReg = 0;

void setShiftReg(byte output)
{
  // Initialize all the pins
  for(int i = 0; i < SHIFT_PINS; i++)
  {
    pinMode(ShiftPins[i], OUTPUT);
  }
  // Set shift clock to low
  digitalWrite(SHFT_CLK_PIN, LOW);
  // Reset shift register
  digitalWrite(RESET_PIN, LOW);
  // clear reset of shift register
  digitalWrite(RESET_PIN, HIGH);

  //ShiftOut the value
  shiftOut(SER_IN_PIN, SHFT_CLK_PIN, LSBFIRST, output);
  
  //Latch in data to output
  digitalWrite(LATCH_PIN, LOW);
  digitalWrite(LATCH_PIN, HIGH);
  digitalWrite(LATCH_PIN, LOW);
};

