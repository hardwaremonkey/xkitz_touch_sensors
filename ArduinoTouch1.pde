/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
AndroidTouch1
 Matt Oppenheim Feb 2012
 Integrating USB Shield and XKitz touch sensor
 The data is sent as:
 {R or L}, active_channel
 R = channel on, L = channel off, active_channel is a byte
 In the event of multiple channels being active, each active channel is sent, the lowest
 first.
 v1.0 March '12 - working with two boards, channels numbered 0-15
 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*

#include <XkitzXwireSerial.h>
#include <Max3421e.h>
#include <Usb.h>
#include <AndroidAccessory.h>
// Bit manipulation definitions
#define bit(num) (1 << num) // creates a bit mask
#define bit_set(v, m) ((v) |=(m)) // Sets the bit
// e.g. bit_set (PORTD, bit(0) | bit(1));
#define bit_clear(v, m) ((v) &=  ~(m)) // Clears the bit
#define bit_toggle(v, m) ((v) ^= (m)) // toggle the bit
#define bit_read(v, m) ((v) & (m))  // read a bit and see if it is set
#define bit_test(v,m)     ((v) && (m))
// Initiate the Xwire library
XkitzXwireSerial XSerial(SERIAL_PIN);    // Arduino Rx/Tx is pin 10 (range is 2-12)
byte active_channels = 0x00; // which channels are active, 1 bit per channel
byte board0=0x1F, board1=0x1B; // Board IDs
byte oscPin = 5;
byte op = 45; 
byte minPulseSep = 50;
long lastEventTime = 0;
long lastTimerTime = 0;
long timerPeriod = 500l;
long lastLogTime = 0;
long logPeriod = 60000l;
int count = 0;

AndroidAccessory acc("Matt Oppenheim",
		     "ArduinoTouch",
		     "Touch Sensor Accessory",
		     "1.0",
		     "https://sites.google.com/site/hardwaremonkey/home",
		     "0000000012345678");

void listXwireBoards(uint8_t num_boards) {
  uint8_t i,j;
  uint8_t boardID;
  uint8_t board0=0x1F, board1=0x1B; // Board IDs for test
  uint16_t XwireRev;
  
    Serial.print("Xwire Library Revision: ");
    XwireRev = XSerial.XwireRevision();
    Serial.println(XwireRev, HEX);

    Serial.println("");

    Serial.print("Xwire Enumeration: ");
    Serial.print(num_boards, HEX);
    Serial.print(" of ");
    Serial.print(NUM_BOARDS, HEX);
    Serial.println(" Xwire boards found");
  

    for (i=1; i<=num_boards; i+=1){
        boardID = (XSerial.XwireInqBoardID(i));

        Serial.print("XwireInqBoardID: Node_ID = ");
        Serial.print(i, HEX);
        Serial.print(", ");
        Serial.print("Board ID = ");
        Serial.print(boardID, HEX);
        Serial.print(", ");
        Serial.print(" FW Rev: ");
        Serial.print((XSerial.boardArray[i-1][4]), HEX);
        Serial.print(" PCB Rev: ");
        Serial.print((XSerial.boardArray[i-1][5]), HEX);
        Serial.print(" Device ID: ");
        Serial.print((XSerial.boardArray[i-1][6]), HEX);
        Serial.print(" Mfgr ID: ");
        if (XSerial.boardArray[i-1][7] == 'X')
            Serial.println("Xkitz");
        else
            Serial.println("Unknown");
        }

    Serial.println("");
  
    for (i=1; i<=num_boards; i+=1){
      boardID = (XSerial.XwireInqBoardID(i));
      i = XSerial.XwireInqNodeID(boardID);
      Serial.print("XwireInqNodeID: Board ID = ");
      Serial.print(boardID, HEX);
      Serial.print(" Node_ID = ");
      Serial.println(i, HEX);
    }
    
      Serial.println("");
  }


void setup() {
  uint8_t num_boards;

  XSerial.begin();	  // start the Xwire protocal
  Serial.begin(115200);   // start serial port for reporting

  Serial.println("Starting Xkitz XCTS-8A Diagnostic");
  Serial.println("");
    
  // run Xwire enumeration
  // finds and catalogs all attached Xwire boards, reports the number found
  num_boards = (XSerial.XwireEnum());
  
  Serial.println("Enumeration done");
    
  if (num_boards != 0) {
    listXwireBoards(num_boards);
  }
  else {
    Serial.println("No Xwire boards found - nothing to do!");
  }
  pinMode(oscPin, OUTPUT);
  analogWrite(oscPin, op);
  acc.powerOn(); // power up USB shield. If the shield is not on,
  // there will be an OSCIRQ error
  Serial.println("ArduinoTouch1 ");
}

void serviceTouch(byte boardID, byte data){
  byte i, channel; 
// check which bits of the passed data are set = active channels 
   for (i=0; i<=7; i++){
// if data shows a channel is active and this is not already flagged in active_channels
// then it must have just been turned on
     if (bit_read(data,bit(i)) && !bit_read(active_channels, bit(i))){
       channel = i; // the channel that is activated
        if (boardID == board0) { // 2nd board, sensors 8-15
        channel += 8; // renumber channels to be 8-15 for the second board
        }
       Serial.print("board = ");
       Serial.print(boardID, HEX);
       Serial.print(" ON channel = ");
       Serial.println(channel,HEX);
       //delay(10); // Allows receiving software time to react
       bit_set(active_channels, bit(i)); // set the bit high for the active channel
       sendMessage('R', channel); // transmit channel on to Android       
     } // if
// clear active_channel when the channel goes low
// if channel is low, but the bit in active_channels is high, then it must have been 
// just turned off
    if(!bit_read(data,bit(i)) && bit_read(active_channels, bit(i))) {
      channel = i;
      if (boardID == board0) { // 2nd board, sensors 8-15
        channel += 8; // renumber channels to be 8-15
      }
      Serial.print("board = ");
      Serial.print(boardID, HEX);
      Serial.print(" OFF channel = ");
      Serial.println(channel,HEX);
      sendMessage('L', channel); // transmit channel off to Android
      bit_clear(active_channels, bit(i)); // set the bit low for the deactived channel 
      //delay(10); // Allows receiving software time to react  
    } // if
   }// for
} // service_data

void loop()
{
  uint8_t touchData, board; // active touch channel, active board ID, counter
 // check each of the Xkitz boards for a channel event.
   // If there is data from the Xkitz, find the active channel number
   if (XSerial.XwireRead() != 0) {
    //if Xwire command == Read_Reg AND the register address == 0x0 then
    //it's a valid register read command from an Xwire device, report it
       if ((XSerial.RxPacketBuf[2] == 0x40) && (XSerial.RxPacketBuf[3] == 0x0)) {
         board = XSerial.XwireInqBoardID(XSerial.RxPacketBuf[1]);
         touchData = XSerial.RxPacketBuf[4];
//         Serial.print("Read boardID = "); // debugging
//         Serial.println(board,HEX); // debugging
         serviceTouch(board,touchData); // finds out which channels are active
         // and transmits that data to Android
          } // ~if
       } // ~if (XSerial.XwireRead() != 0)
} // ~loop


//send data to Android
//4 byte packet contained in msg[4]
void sendMessage(char flag, int data)
{
  if (acc.isConnected()) 
  {
    byte msg[4];
    msg[0] = 0x04;
    msg[1] = (byte) flag;
   // msg[2] = cpm >> 8; // cpm is 2 bytes, 1st byte -> msg[2]
   // msg[3] = cpm & 0xff; // 2nd byte of cpm -> msg[3]
   msg[2] = 0x00;
   msg[3] = data;
    acc.write(msg, 4); // write msg as 4 bytes
    Serial.print(" Sending flag ");
    Serial.print(flag,HEX);
    Serial.print(" data ");
    Serial.println(data, HEX);
  }
}


