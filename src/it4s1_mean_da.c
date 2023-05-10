// *********************************************************************
// Create mean amplitude and DA map
// Input are SLC's
// ---------------------------------------------------------------------
// AUTHOR    : Andy Hooper
// ---------------------------------------------------------------------
// WRITTEN   : 04.08.2003
//  Changed by Milan Lazecky, 16-01-2018

#include <string.h> 
using namespace std;

#include <iostream>  
using namespace std;
     
#include <fstream>  
using namespace std;

#include <complex>  
using namespace std;
     
#include <vector>  
using namespace std;
     
#include <cmath>  
using namespace std;
     
#include <cstdio>
using namespace std;     

#include <cstdlib>     
using namespace std;     

#include <climits>     
using namespace std;     

// =======================================================================
// Start of program 
// =======================================================================
int cshortswap( complex<short>* f )
{
  char* b = reinterpret_cast<char*>(f);
  complex<short> f2;
  char* b2 = reinterpret_cast<char*>(&f2);
  b2[0] = b[1];
  b2[1] = b[0];
  b2[2] = b[3];
  b2[3] = b[2];
  f[0]=f2;
}

int cfloatswap( complex<float>* f )
{
  char* b = reinterpret_cast<char*>(f);
  complex<float> f2;
  char* b2 = reinterpret_cast<char*>(&f2);
  b2[0] = b[3];
  b2[1] = b[2];
  b2[2] = b[1];
  b2[3] = b[0];
  b2[4] = b[7];
  b2[5] = b[6];
  b2[6] = b[5];
  b2[7] = b[4];
  f[0]=f2;
}
int longswap( int32_t* f )
{
  char* b = reinterpret_cast<char*>(f);
  int32_t f2;
  char* b2 = reinterpret_cast<char*>(&f2);
  b2[0] = b[3];
  b2[1] = b[2];
  b2[2] = b[1];
  b2[3] = b[0];
  f[0]=f2;
}

int main(int  argc, char *argv[] ) {   // [MA]  long --> int for gcc 4.3.x 

try {
 
  if (argc < 3)
  {	  
     cout << "Usage: it4s1_mean_da parmfile patch.in da.flt mean_amp.flt" << endl << endl;
     cout << "input parameters:" << endl;
     cout << "  parmfile (input) amplitude dispersion threshold" << endl;
     cout << "                   width of amplitude files (range bins)" << endl;
     cout << "                   SLC file names & calibration constants" << endl;
     cout << "  patch.in (input) location of patch in rg and az" << endl;
     cout << "  da.flt   (output) amplitude dispersion" << endl << endl;
     cout << "  mean_amp.flt (output) mean amplitude of image" << endl << endl;
     throw "";
  }   
     
  const char *daoutname; // [MA]
  if (argc < 4) 
     daoutname="da.flt";
  else daoutname = argv[3];   
     
  const char *meanoutname; // [MA]
  if (argc < 5) 
     meanoutname="mean_amp.flt";
  else meanoutname = argv[4];   
  
  ifstream parmfile (argv[1], ios::in);
  if (! parmfile.is_open()) 
  {	  
      cout << "Error opening file " << argv[1] << "\n"; 
      throw "";
  }    
   
      
  char line[256];
  int num_files = 0;
  
  int width = 0;
  float D_thresh = 0;

  parmfile >> D_thresh;

  parmfile >> width;
  cout << "width = " << width << "\n";	  
  parmfile.getline(line,256);
  int savepos=parmfile.tellg();
  parmfile.getline(line,256);
  while (! parmfile.eof())
  {
      parmfile.getline(line,256);
      num_files++;
  }    
  //parmfile >> num_files;
  parmfile.clear();
  parmfile.seekg(savepos);
  char ampfilename[256];
  ifstream* ampfile   = new ifstream[num_files];
  register float* calib_factor = new float[num_files];
      
  for (register int i=0; i<num_files; ++i) 
  {
    parmfile >> ampfilename >> calib_factor[i];
    ampfile[i].open (ampfilename, ios::in|ios::binary);
    cout << "opening " << ampfilename << "...\n";

    if (! ampfile[i].is_open())
    {	    
        cout << "Error opening file " << ampfilename << "\n"; 
	throw "";
    }

    char header[32];
    long magic=0x59a66a95;
    ampfile[i].read(header,32);
    if (*reinterpret_cast<long*>(header) == magic)
        cout << "sun raster file - skipping header\n";
    else ampfile[i].seekg(ios::beg); 
  }
  
  parmfile.close();
  cout << "number of amplitude files = " << num_files << "\n";

  ifstream patchfile (argv[2], ios::in);
  if (! patchfile.is_open()) 
  {	  
      cout << "Error opening file " << argv[2] << "\n"; 
      throw "";
  }    

  int rg_start=0;
  int rg_end=INT_MAX;
  int az_start=0;
  int az_end=INT_MAX;
  patchfile >> rg_start;
  patchfile >> rg_end;
  patchfile >> az_start;
  patchfile >> az_end;
  patchfile.close();

  // [A0] determine size of a patch
  int patch_lines = az_end-az_start+1;
  int patch_width = rg_end-rg_start+1;

  const int sizeoffloat=4; // [MA] size of a pixel
  int sizeofelement; // [MA] size of a pixel
  sizeofelement = sizeof(float);

  const int linebytes = width*sizeofelement*2;  // bytes per line in amplitude files (SLCs)
  const int patch_linebytes =  patch_width*sizeofelement*2;

  filebuf *pbuf;
  long size;
  long numlines;

  // get pointer to associated buffer object
  pbuf=ampfile[0].rdbuf();

  // get file size using buffer's members
  size=pbuf->pubseekoff (0,ios::end,ios::in);
  pbuf->pubseekpos (0,ios::in);
  numlines=size/width/sizeofelement/2;

  cout << "number of lines per file = " << numlines << "\n";	  
  
  cout << "patch lines = " << patch_lines  << endl;
  cout << "patch width = " << patch_width  <<  endl;

  ofstream daoutfile(daoutname,ios::out);
  ofstream meanoutfile(meanoutname,ios::out);
 
  char* buffer = new char[num_files*patch_linebytes]; // used to store 1 line of all amp files
  complex<float>* bufferf = reinterpret_cast<complex<float>*>(buffer); 
  complex<short>* buffers = reinterpret_cast<complex<short>*>(buffer);

  register int y=0;                                      // amplitude files line number

  register long long pix_start;
  register long long pos_start;
  pix_start= (long long)(az_start-1)*width+(rg_start-1); // define pixel number of start of 1st line of patch
  pos_start= pix_start*sizeofelement*2; // define position of start of 1st line of patch
                                                                               // on SLC file.
  for (register int i=0; i<num_files; i++)              // read in first line from each amp file
  {
    ampfile[i].seekg (pos_start, ios::beg);
    ampfile[i].read (&buffer[i*patch_linebytes], patch_linebytes);
  } 
     
  while (! ampfile[1].eof() && y < patch_lines) 
  {
     if (y >=0) // was (y >= az_start-1)
       {
       for (register int x=0; x<patch_width; x++) // for each pixel in range (width of the patch)
       {
     
        register float sumamp = 0;
        register float sumampsq = 0;
        int amp_0 =0;
        for (register int i=0; i<num_files; i++)        // for each amp file
	   {
           complex<float> camp; // get amp value
           camp=bufferf[i*patch_width+x]; // get amp value

           register float amp=abs(camp)/calib_factor[i]; // get amp value
           if (amp <=0.00005) // do not use amp = 0 values for calculating the AD and set flag to 1
           {
            amp_0=1;
            sumamp=0;
            continue  ; 
           }else
           {
           sumamp+=amp;
           sumampsq+=amp*amp;
           }
         }
	
        meanoutfile.write(reinterpret_cast<char*>(&sumamp),sizeoffloat);	
        register float D_sq=1;

        if ( sumamp > 0)
        {
      //Amplitude disperion^2 
	    D_sq=num_files*sumampsq/(sumamp*sumamp) - 1; // 1-var/mean^2
        }

        daoutfile.write(reinterpret_cast<char*>(&D_sq),sizeoffloat);	
        
       } //for loop x++           
     } // endif y >=0

     y++;

     for (register int i=0; i<num_files; i++)           // read in next line from each amp file
     {
        ampfile[i].seekg (linebytes-patch_linebytes, ios::cur);  // [MA]
        ampfile[i].read (&buffer[i*patch_linebytes], patch_linebytes);
     } 
     
     if (y/100.0 == rint(y/100.0))
        cout << y << " lines processed\n";
  }  
  daoutfile.close();
  meanoutfile.close();
  }
  catch( char * str ) {
     cout << str << "\n";
     return(999);
  }   
  catch( ... ) {
    return(999);
  }

  return(0);
       
};
