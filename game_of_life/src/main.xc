#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 512                    //image height
#define  IMWD 512                   //image width
#define  WORKER_COUNT 8
#define  LINES IMHT
#define  CLUSTERS IMWD/8
#define  LINES_PER_WORKER LINES/WORKER_COUNT
//define LED colours
#define  RESET 0
#define  SEPARATE_GREEN 1
#define  BLUE 2
#define  GREEN 4
#define  RED 8

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


char infname[] = "512x512.pgm";     //put your input image path here
char outfname[] = "512testout.pgm"; //put your output image path here

int showLEDs(out port p, chanend fromDist){
    int pattern; //1st bit...separate green LED
                   //2nd bit...blue LED
                   //3rd bit...green LED
                   //4th bit...red LED
      while (1) {
//        select {
//            case fromDataOutStream :> pattern:
//                break;
//            case fromDataInStream :> pattern:
//                break;
//
//        }
          fromDist :> pattern;
        p <: pattern;                //send pattern to LED port
      }
      return 0;
}

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
    for( int cluster = 0; cluster < CLUSTERS; cluster++ ) {
        uchar curCluster = 0;
        for(int bit=0; bit < 8; bit++){
            int pixelPos = (cluster * 8) + bit;
            uchar val = line[pixelPos];
            curCluster |= ((val==255) << (7-bit));
        }
            c_out <: curCluster;
     // printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}


int getCellFromCluster(uchar cluster, int position){
    return (cluster >> (7-position)) & 1;
}

void receiveBoardFromWorkers(chanend toWorker[WORKER_COUNT], uchar board[LINES][CLUSTERS], int *alive){

    for(int worker=0; worker < WORKER_COUNT; worker++)
        toWorker[worker] <: ACTION_RETURN_DATA;

    for(int worker = 0; worker < WORKER_COUNT; worker++){
                   toWorker[worker] <: 1;
                   for(int line=0; line < LINES_PER_WORKER; line++){
                       int startingLine = ((worker*LINES_PER_WORKER) + LINES) % LINES;
                       int currentLine = (startingLine + line) % LINES;
                       for(int cluster=0; cluster<CLUSTERS; cluster++){
                           uchar receivedCluster;
                           toWorker[worker] :> receivedCluster;
                           board[currentLine][cluster] = receivedCluster;
                           for(int pos = 0; pos < 8; pos++)
                               if(getCellFromCluster(receivedCluster, pos) == 1)
                                   (*alive)++;
                       }
                   }
               }

}

void exportData(uchar board[LINES][CLUSTERS], chanend c_out){
    printf("Starting to output data...\n");
    uchar val;

    //Outputting data
    for(int line = 0; line < LINES; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            uchar curCluster = board[line][cluster];
            for(int pos = 0; pos < 8; pos++){   //go through each bit
                val = getCellFromCluster(curCluster, pos)*255;
                c_out <: val;
            }
        }
    }
}

void iterateWorkers(chanend toWorker[WORKER_COUNT]){
    for(int worker=0; worker < WORKER_COUNT; worker++)
        toWorker[worker] <: ACTION_ITERATE;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend toWorker[WORKER_COUNT], chanend fromAcc, chanend fromButtons, chanend toLEDs)
{
    uchar board[LINES][CLUSTERS];

    int alive       = 0;
    int iteration   = 0;
    int button      = 0;

    timer time;
    const unsigned int timePeriod       = 100000000;        //1 second
    const unsigned int timeReset        = 20 * 100000000;   //time interval for timer reset
    unsigned int timeStart;
    unsigned int timeFinish;
    unsigned int timeTaken;


    //Waiting for button 14 to be pressed to start the game
    printf("Waiting for button press..\n");
    while(button != 14){
        fromButtons :> button;
    }


    //Starting up and wait for tilting of the xCore-200 Explorer
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );
    toLEDs <: GREEN;

    //Storing image data
    printf( "Processing...\n" );
    uchar val;
    for(int line = 0; line < LINES; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            c_in :> val;
            board[line][cluster] = val;
        }
    }

    toLEDs <: RESET;
    time :> timeStart;

    //Sending data to workers
    printf("\nSending data to workers...\n");
    for(int worker=0; worker < WORKER_COUNT; worker++){
        for(int line=0; line < LINES_PER_WORKER+2; line++){
            int startingLine = ((worker*LINES_PER_WORKER)- 1 + LINES) % LINES;
            int currentLine = (startingLine + line) % LINES;
            for(int cluster=0; cluster<CLUSTERS; cluster++){
                toWorker[worker] <: board[currentLine][cluster];
            }
        }
    }

    //Game runs forever
    while(1){
        toLEDs <: SEPARATE_GREEN;
        select {

            //Pausing the game if the board is tilted
            case fromAcc :> int tilted:
                if(tilted){
                    toLEDs <: RED;
                    time :> timeFinish;
                    timeTaken += (timeFinish - timeStart)/timePeriod;

                    alive = 0;
                    receiveBoardFromWorkers(toWorker, board, &alive);

                    printf("\nGame is paused\nIteration:%d\nAlive cells:%d\nTime taken:%u\n", iteration, alive, timeTaken); //Kwame I left it like this because otherwise it may get cut-off by another print by another tile...

                    while(tilted){
                        fromAcc :> tilted;
                    }
                    time :> timeStart;
                }
                break;


            //Exporting and printing out the board if the button is pressed
            case fromButtons :> button:
                if(button == 13){
                    toLEDs <: BLUE;
                    time :> timeFinish;
                    timeTaken += (timeFinish - timeStart)/timePeriod;

                    //receive the board from workers
                    alive = 0;
                    receiveBoardFromWorkers(toWorker, board, &alive);
                    exportData(board, c_out);

                    printf("\nBoard has been exported\nIteration:%d\nAlive cells:%d\nTime taken:%u\n", iteration, alive, timeTaken);
                    time :> timeStart;
                }
                break;

            //Handles the timer by reseting it correctly and not allowing it to overflow
            case time when timerafter(timeStart + timeReset) :> void:
                   time :> timeStart;
                   timeTaken += timeReset/timePeriod;
                   continue;


            //The default action will continue iterating
            default:
                iterateWorkers(toWorker);
                iteration++;
                toLEDs <: RESET;
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

    uchar currentPixel = getCellFromCluster(currentCluster, pixel);
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
            fromDist :> startSendingDataBack;
            if(startSendingDataBack == 1){
                //sending data back to distributer
                for(int line = 1; line <= LINES_PER_WORKER; line++){
                    for(int cluster = 0; cluster < CLUSTERS; cluster++){
                        fromDist <: nextGenBoard[line][cluster];
                    }
                }
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
//        for( int y = 0; y < IMHT; y++ ) {
//          for( int x = 0; x < IMWD; x++ ) {
//            c_in :> line[ x ];
//          }
//          _writeoutline( line, IMWD );
//          printf( "DataOutStream: Line written...\n" );
//        }

        //Prints out the board
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
  int wasTilted = 0;

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

    if (x>30) {
        wasTilted = 1;
        toDist <: 1;
    }else if(wasTilted && x<=30){
        wasTilted = 0;
        toDist <: 0;
    }

//    else{
//        toDist <: 0;
//    }
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
chan workersDist[8];
chan workersTW[8];
chan cButtons, cLEDs;

par {
    on tile[0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]:orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]:DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile[0]:DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    on tile[0]:distributor(c_inIO, c_outIO, workersDist, c_control, cButtons, cLEDs);//thread to coordinate work on image
    on tile[0]:buttonListener(buttons, cButtons);
    on tile[0]:showLEDs(leds, cLEDs);

    on tile[1]:worker(0, workersDist[0], workersTW[7], workersTW[0]);
    on tile[1]:worker(1, workersDist[1], workersTW[0], workersTW[1]);
    on tile[1]:worker(2, workersDist[2], workersTW[1], workersTW[2]);
    on tile[1]:worker(3, workersDist[3], workersTW[2], workersTW[3]);
    on tile[1]:worker(4, workersDist[4], workersTW[3], workersTW[4]);
    on tile[1]:worker(5, workersDist[5], workersTW[4], workersTW[5]);
    on tile[1]:worker(6, workersDist[6], workersTW[5], workersTW[6]);
    on tile[1]:worker(7, workersDist[7], workersTW[6], workersTW[7]);



  }

  return 0;
}
