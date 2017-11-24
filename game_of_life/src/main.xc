// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                 //image height
#define  IMWD 16                  //image width
#define  WORKER_COUNT 4
#define  LINES IMHT
#define  CLUSTERS IMWD/8
#define  LINES_PER_WORKER LINES/WORKER_COUNT

#define ACTION_ITERATE 1
#define ACTION_RETURN_DATA 2

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]:port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
on tile[0]:port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6


char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here

//int showLEDs(out port p, chanend fromDataInStream, chanend fromDataOutStream){
//    int pattern; //1st bit...separate green LED
//                   //2nd bit...blue LED
//                   //3rd bit...green LED
//                   //4th bit...red LED
//      while (1) {
//        select {
//            case fromDataOutStream :> pattern:
//                break;
//            case fromDataInStream :> pattern:
//                break;
//
//        }
//          //receive new pattern from visualiser
//        p <: pattern;                //send pattern to LED port
//      }
//      return 0;
//}

void buttonListener(in port b, chanend toDist){
    int r;
      while (1) {
        b when pinseq(15)  :> r;    // check that no button is pressed
        b when pinsneq(15) :> r;    // check if some buttons are pressed
        if(r == 13 || r == 14)
            toDist <: r;
      }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend toWorker[workerCount] , uint workerCount, chanend fromAcc, chanend fromButtons)
{
    uchar val;
    uchar board[LINES][CLUSTERS];
    uchar nextGenBoard[LINES][CLUSTERS];

    printf("Waiting for button press..\n");
    int button = 0;

    while(button != 14){
        fromButtons :> button;
    }


    //Starting up and wait for tilting of the xCore-200 Explorer
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );

    printf( "Processing...\n" );
    //Storing image data
    for(int line = 0; line < LINES; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            uchar curCluster = 0;               //cluster contains 8 cells
            for(int bit = 0; bit < 8; bit++){   //go through each bit
                c_in :> val;
                curCluster |= ((val==255) << (7-bit));
            }
            board[line][cluster] = curCluster;
        }
    }

    printf("\nSending data to workers...\n");
    //Sending data to workers
    for(int worker=0; worker < 4; worker++){
        for(int line=0; line < LINES_PER_WORKER+2; line++){
            int startingLine = ((worker*LINES_PER_WORKER)- 1 + LINES) % LINES;
            int currentLine = (startingLine + line) % LINES;
            for(int cluster=0; cluster<CLUSTERS; cluster++){
                toWorker[worker] <: board[currentLine][cluster];
            }
        }
    }

    while(1){
        select {
            case fromButtons :> button:
                if(button == 13){
                    //print out info
                    for(int worker=0; worker < WORKER_COUNT; worker++){
                           toWorker[worker] <: ACTION_RETURN_DATA;

                           for(int worker = 0; worker < 4; worker++){
                               toWorker[worker] <: 1;
                               //printf("Starting to receive data from worker %d\n", worker);
                               for(int line=0; line < LINES_PER_WORKER; line++){
                                   int startingLine = ((worker*LINES_PER_WORKER) + LINES) % LINES;
                                   int currentLine = (startingLine + line) % LINES;
                                   //printf("Line:%d - ", currentLine);
                                   for(int cluster=0; cluster<CLUSTERS; cluster++){
                                       uchar receivedCluster;
                                       toWorker[worker] :> receivedCluster;
                                       nextGenBoard[currentLine][cluster] = receivedCluster;
                                       //printf("%02X ", nextGenBoard[currentLine][cluster]);
                                   }
                                  // printf("\n");
                               }
                               //printf("Successfully received data from worker:%d\n", worker);
                           }

                           printf("Starting to output data...\n");
                           //Outputting data
                           for(int line = 0; line < LINES; line++){
                               for(int cluster = 0; cluster < CLUSTERS; cluster++){
                                   uchar curCluster = nextGenBoard[line][cluster];
                                   for(int bit = 0; bit < 8; bit++){   //go through each bit
                                       val = ((curCluster >> (7-bit)) & 1)*255;
                                       c_out <: val;
                                   }
                               }
                           }
                       }
                }
                break;
            default:
                for(int worker=0; worker < WORKER_COUNT; worker++){
                    toWorker[worker] <: ACTION_ITERATE;
                }
                printf("Iteration\n");
                break;
        }
    }

    //Receiving data from workers
    //printf("Receiving data from workers!\n");
//    int workersDone = 0;
//    while(workersDone != 4){
//        select{
//            case toWorker[int worker] :> uchar receivedCluster:
//                for(int line=0; line < LINES_PER_WORKER; line++){
//                    for(int cluster=0; cluster<CLUSTERS; cluster++){
//                        int startingLine = ((worker*LINES_PER_WORKER) - 1 + LINES) % LINES;
//                        int currentLine = (startingLine + line) % LINES;
//                        nextGenBoard[currentLine][cluster] = receivedCluster;
//                    }
//                    printf("Successfully received line:%d from worker:%d.\n", line, worker);
//                }
//                printf("Successfully received data from worker:%d\n", worker);
//                workersDone++;
//                break;
//        }
//    }
//


}

uchar evolution(uchar currentPixel, int aliveNeigh){

    if(aliveNeigh < 2 || aliveNeigh > 3) return 0;
    if(aliveNeigh == 3) return 1;

    return currentPixel;
}

uchar nextGen(int pixel, int cluster, int line, uchar board[LINES_PER_WORKER + 2][CLUSTERS]){
    uchar currentCluster = board[line][cluster];
    int top, bottom, left, right, tLeft, tRight, bLeft, bRight;
    int alive = 0;
    int clus = CLUSTERS;

    int leftCluster =  ((cluster - 1) + clus) % clus;
    int rightCluster = (cluster + 1) % clus;

    top = ((board[line - 1][cluster]) >> (7-pixel)) & 1;
    bottom = ((board[line + 1][cluster]) >> (7-pixel)) & 1;

    left = ((board[line][cluster]) >> (7-pixel+1)) & 1;
    right = ((board[line][cluster]) >> (7-pixel-1)) & 1;

    if(pixel == 0){
        left = (board[line][leftCluster]) & 1;
        tLeft = (board[line - 1][leftCluster]) & 1;
        bLeft = (board[line + 1][leftCluster]) & 1;
        tRight = ((board[line - 1][cluster]) >> (7-pixel-1)) & 1;
        bRight = ((board[line + 1][cluster]) >> (7-pixel-1)) & 1;

    }else if(pixel == 7){
        right  = ((board[line][rightCluster]) >> 7) & 1;
        tRight = ((board[line - 1][rightCluster]) >> 7) & 1;
        bRight = ((board[line + 1][rightCluster]) >> 7) & 1;
        tLeft = ((board[line - 1][cluster]) >> (7-pixel+1)) & 1;
        bLeft = ((board[line + 1][cluster]) >> (7-pixel+1)) & 1;
    }else
    {
        tLeft = ((board[line - 1][cluster]) >> (7-pixel+1)) & 1;
        bLeft = ((board[line + 1][cluster]) >> (7-pixel+1)) & 1;
        tRight = ((board[line - 1][cluster]) >> (7-pixel-1)) & 1;
        bRight = ((board[line + 1][cluster]) >> (7-pixel-1)) & 1;
    }

    alive = tLeft + top + tRight + left + right + bLeft + bottom + bRight;

    uchar currentPixel = (currentCluster >> (7 - pixel)) & 1;
    return evolution(currentPixel, alive);
}

void worker(int id, chanend fromDist, chanend leftWorker, chanend rightWorker){
    uchar board[LINES_PER_WORKER+2][CLUSTERS];
    uchar nextGenBoard [LINES_PER_WORKER+2][CLUSTERS];


    //receiving data from the distributer
    for(int line = 0; line < LINES_PER_WORKER+2; line++)
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            fromDist :> board[line][cluster];
            nextGenBoard[line][cluster] = 0;
        }

    int action;
    //updating data for set iterations
    while(1){
        fromDist :> action;

        if(action == ACTION_ITERATE){
            //updating the board
            for(int line = 1; line <= LINES_PER_WORKER; line++)
                for(int cluster = 0; cluster < CLUSTERS; cluster++){
                    nextGenBoard[line][cluster] = 0;
                    for(int pixel = 0; pixel < 8; pixel++){
                       uchar result = nextGen(pixel, cluster, line, board);
                       nextGenBoard[line][cluster] |= ((result & 1)<<(7-pixel));
                    }
                }

            //updating oldBoard
            for(int i=0; i<LINES_PER_WORKER+2; i++)
                for(int j=0; j<CLUSTERS; j++)
                    board[i][j] = nextGenBoard[i][j];

            //communications between workers
            for(int cluster = 0; cluster<CLUSTERS; cluster++){
                if(id%2==0){
                    rightWorker <: board[LINES_PER_WORKER][cluster];
                    rightWorker :> board[LINES_PER_WORKER + 1][cluster];
                    leftWorker :> board[0][cluster];
                    leftWorker <: board[1][cluster];
                }else{
                    leftWorker :> board[0][cluster];
                    leftWorker <: board[1][cluster];
                    rightWorker <: board[LINES_PER_WORKER][cluster];
                    rightWorker :> board[LINES_PER_WORKER + 1][cluster];
                }
            }
        }
        else if(action == ACTION_RETURN_DATA){
            int startSendingDataBack = 0;
            fromDist :> startSendingDataBack ;
            if(startSendingDataBack == 1){
                //sending data back to distributer
                for(int line = 1; line <= LINES_PER_WORKER; line++)
                    for(int cluster = 0; cluster < CLUSTERS; cluster++)
                        fromDist <: nextGenBoard[line][cluster];
            }
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  while(1){
      //Open PGM file
        printf( "DataOutStream: Start...\n" );
        res = _openoutpgm( outfname, IMWD, IMHT );
        if( res ) {
          printf( "DataOutStream: Error opening %s\n.", outfname );
          return;
        }

        //Compile each line of the image and write the image line-by-line
      //  for( int y = 0; y < IMHT; y++ ) {
      //    for( int x = 0; x < IMWD; x++ ) {
      //      c_in :> line[ x ];
      //    }
      //    _writeoutline( line, IMWD );
      //    printf( "DataOutStream: Line written...\n" );
      //  }

        for( int y = 0; y < IMHT; y++ ) {
          _readinline( line, IMWD );
          for( int x = 0; x < IMWD; x++ ) {
            c_in :> line[ x ];
            printf( "-%4.1d ", line[ x ] ); //show image values
          }
          printf( "\n" );
        }

        //Close the PGM image
        _closeoutpgm();
        printf( "DataOutStream: Done...\n" );
  }

  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        //toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan workersOut[4];
chan workersIn[4];
chan cButtons;

par {
    on tile[0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]:orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]:DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile[0]:DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    on tile[0]:distributor(c_inIO, c_outIO, workersOut, 4, c_control, cButtons);//thread to coordinate work on image
    on tile[0]:buttonListener(buttons, cButtons);
    //on tile[0]:showLEDs(cLeds, cLeds);

    on tile[1]:worker(0, workersOut[0], workersIn[3], workersIn[0]);
    on tile[1]:worker(1, workersOut[1], workersIn[0], workersIn[1]);
    on tile[1]:worker(2, workersOut[2], workersIn[1], workersIn[2]);
    on tile[1]:worker(3, workersOut[3], workersIn[2], workersIn[3]);


  }

  return 0;
}
