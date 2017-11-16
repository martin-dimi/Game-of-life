// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define  WORKER_COUNT 4
#define  LINES IMHT
#define  CLUSTERS IMWD/8
#define  LINES_PER_WORKER LINES/WORKER_COUNT

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]:port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
on tile[0]:port p_sda = XS1_PORT_1F;

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
void distributor(chanend c_in, chanend c_out, chanend toWorker[workerCount] , uint workerCount, chanend fromAcc)
{
    uchar val;
    uchar board[LINES][CLUSTERS];
    uchar nextGenBoard[LINES][CLUSTERS];

    //Starting up and wait for tilting of the xCore-200 Explorer
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );
    //fromAcc :> int value;

    printf( "Processing...\n" );
    //Storing image data
    for(int line = 0; line < LINES; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            uchar curCluster = 0;               //cluster contains 8 cells
            for(int bit = 0; bit < 8; bit++){   //go through each bit
                c_in :> val;
                curCluster |= ((val==255) << 7-bit);
            }
            board[line][cluster] = curCluster;
        }
    }

    printf("\nSending data to workers...\n");
    //Sending data to workers
    for(int worker=0; worker < WORKER_COUNT; worker++)
        for(int line=0; line < LINES_PER_WORKER+2; line++)
            for(int cluster=0; cluster<CLUSTERS; cluster++){
                int startingLine = (worker*LINES_PER_WORKER) - 1 + LINES;
                int currentLine = (startingLine + line) % LINES;
                toWorker[worker] <: board[currentLine][cluster];
            }

    printf("Data send successfully!\n");

    printf("Receiving data from workers!\n");
    //Receiving data from workers
    select{
        case toWorker[int worker] :> uchar receivedCluster:
            for(int line=0; line < LINES_PER_WORKER; line++){
                for(int cluster=0; cluster<CLUSTERS; cluster++){
                    int startingLine = ((worker*LINES_PER_WORKER) - 1 + LINES) % LINES;
                    int currentLine = startingLine + line;

                    nextGenBoard[currentLine][cluster] = receivedCluster;
                }
                printf("Successfully received line:%d from worker:%d.\n", line, worker);
            }
            printf("Successfully received data from worker:%d\n", worker);
            break;
    }


    printf("Starting to output data...\n");
    //Outputting data
    for(int line = 0; line < LINES; line++){
            for(int cluster = 0; cluster < CLUSTERS; cluster++){
                uchar curCluster = nextGenBoard[line][cluster];
                for(int bit = 0; bit < 8; bit++){   //go through each bit
                    val = ((curCluster << (7-bit)) & 1)*255;
                    c_out <: val;
                }
            }
        }

}

uchar evolution(uchar currentPixel, int aliveNeigh){

    if(aliveNeigh < 2 || aliveNeigh > 3) return 0;
    if(aliveNeigh == 3) return 1;

    return currentPixel;
}

    uchar nextGen(int pixel, int cluster, int line, uchar board[(IMHT / WORKER_COUNT) + 2][IMWD / 8]){
        const int clusters = IMWD / 8;
        uchar currentCluster = board[line][cluster];
        int neighbours = 0;


        for(int currentLine = (line - 1); currentLine <= line + 1; currentLine++){
            for(int currentCol = (pixel - 1); currentCol <= pixel + 1; currentCol++){
                uchar extraCluster = currentCluster;

                if(!(currentCol == pixel && currentLine == line)){
                    if(currentCol == -1){
                        extraCluster = board[currentLine][(cluster-1 + (IMWD/8))%clusters]; //remember to change mod
                    }
                    if(currentCol == 8){
                        extraCluster = board[currentLine][(cluster+1)%clusters];
                    }
                    if(((extraCluster >> (7-currentCol)) & 1) == 1) neighbours++;
                }
             }
        }
        uchar currentPixel = (currentCluster << (7 - pixel)) & 1;
        return evolution(currentPixel ,neighbours);
    }

void worker(int id, chanend fromDist, chanend leftWorker, chanend rightWorker){
    uchar board[LINES_PER_WORKER+2][CLUSTERS];
    uchar nextGenBoard [LINES_PER_WORKER+2][CLUSTERS];

    //receiving data
    for(int line = 0; line < LINES_PER_WORKER+2; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++)
            fromDist :> board[line][cluster];
    }
    //printf("Worker:%d successully received data!\n", id);



    //updating data for set iterations
    int iterations = 3;
    while(iterations > 0){

        //printf("Worker:%d updating generation.\n", id);
        for(int line = 1; line < LINES_PER_WORKER+1; line++){
            for(int cluster = 0; cluster < CLUSTERS; cluster++){
                for(int pixel = 0; pixel < 8; pixel++){
                   uchar result = nextGen(pixel, cluster, line, board);
                   nextGenBoard[line][cluster] |= (result << (7 - pixel));
                }
            }
        }

        //printf("Worker:%d generation succesfully updated!\n", id);
        for(int cluster = 0; cluster<CLUSTERS; cluster++){
            par{
                leftWorker :> board[0][cluster];
                rightWorker <: board[LINES_PER_WORKER+1][cluster];
            }
        }

        for(int line = 0; line < LINES_PER_WORKER+2; line++){
            for(int cluster = 0; cluster < CLUSTERS; cluster++)
                board[line][cluster] = nextGenBoard[line][cluster];
        }

        //printf("Worker:%d sending data to distributer.\n", id);
        iterations--;
    }

    //printf("Worker:%d sending data to distributer.\n", id);
    //sending data
    for(int line = 1; line < LINES_PER_WORKER+1; line++){
        for(int cluster = 0; cluster < CLUSTERS; cluster++){
            fromDist <: nextGenBoard[line][cluster];
        }
    }
    //printf("Worker:%d data successfully sent to distrubuter!\n", id);
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

par {
    on tile[0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]:orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]:DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile[0]:DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    on tile[0]:distributor(c_inIO, c_outIO, workersOut, 4, c_control);//thread to coordinate work on image

    on tile[1]:worker(0, workersOut[0], workersIn[3], workersIn[1]);
    on tile[1]:worker(1, workersOut[1], workersIn[0], workersIn[2]);
    on tile[1]:worker(2, workersOut[2], workersIn[1], workersIn[3]);
    on tile[1]:worker(3, workersOut[3], workersIn[2], workersIn[0]);

  }

  return 0;
}
