/*

  atomeow - a sample Processing implementation of my article:
  Blue noise sampling using an N-body simulation-based methos  
  https://www.researchgate.net/publication/316709742_Blue_noise_sampling_using_an_N-body_simulation-based_method

  MIT License
  
  Copyright (c) 2021 Kin-Ming Wong (Mike Wong), @artxiels
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

*/

#ifdef GL_ES
precision highp float;
precision highp int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform vec2 u_resolution;
uniform sampler2D u_pos;
uniform sampler2D u_bmpQ;

uniform int   u_simXY;
uniform float u_dotCharge;
uniform int   u_numDots;


//  Utility function to convert 16-bit HALF bits (2 bytes) to 'float'
//  (low-level), **DO NOT CHANGE**
//
float toFloat( int hbits )
{
    int mant = hbits & 0x03ff;            // 10 bits mantissa
    int exp =  hbits & 0x7c00;            // 5 bits exponent
    if( exp == 0x7c00 )                   // NaN/Inf
        exp = 0x3fc00;                    // -> NaN/Inf
    else if( exp != 0 )                   // normalized value
    {
        exp += 0x1c000;                   // exp - 15 + 127
        if( mant == 0 && exp > 0x1c400 )  // smooth transition
            return intBitsToFloat( ( hbits & 0x8000 ) << 16
                                            | exp << 13 | 0x3ff );
    }
    else if( mant != 0 )                  // && exp==0 -> subnormal
    {
        exp = 0x1c400;                    // make it normal
        do {
            mant <<= 1;                   // mantissa * 2
            exp -= 0x400;                 // decrease exp by 1
        } while( ( mant & 0x400 ) == 0 ); // while not normal
        mant &= 0x3ff;                    // discard subnormal bit
    }                                     // else +/-0 -> +/-0
    return intBitsToFloat(                // combine all parts
        ( hbits & 0x8000 ) << 16          // sign  << ( 31 - 15 )
        | ( exp | mant ) << 13 );         // value << ( 23 - 10 )
}


//  Utility function to convert 'float' to 16-bit HALF bits (2 bytes)
//  (low-level), **DO NOT CHANGE**
//
int fromFloat( float fval )
{
    int fbits = floatBitsToInt( fval );
    int sign = fbits >> 16 & 0x8000;          // sign only
    int val = ( fbits & 0x7fffffff ) + 0x1000; // rounded value

    if( val >= 0x47800000 )               // might be or become NaN/Inf
    {                                     // avoid Inf due to rounding
        if( ( fbits & 0x7fffffff ) >= 0x47800000 )
        {                                 // is or must become NaN/Inf
            if( val < 0x7f800000 )        // was value but too large
                return sign | 0x7c00;     // make it +/-Inf
            return sign | 0x7c00 |        // remains +/-Inf or NaN
                ( fbits & 0x007fffff ) >> 13; // keep NaN (and Inf) bits
        }
        return sign | 0x7bff;             // unrounded not quite Inf
    }
    if( val >= 0x38800000 )               // remains normalized value
        return sign | val - 0x38000000 >> 13; // exp - 127 + 15
    if( val < 0x33000000 )                // too small for subnormal
        return sign;                      // becomes +/-0
    val = ( fbits & 0x7fffffff ) >> 23;  // tmp exp for subnormal calc
    return sign | ( ( fbits & 0x7fffff | 0x800000 ) // add subnormal bit
         + ( 0x800000 >> val - 102 )     // round depending on cut off
      >> 126 - val );   // div by 2^(1-(exp-127+15)) and >> 13 | exp=0
}


//  decode color (vec4) to 2x 'HALF' (returned as float)
//  (low-level), **DO NOT CHANGE**
//
vec2 decodeV2(vec4 c) {
  int XH = 0xFF & int(c.a * 255.);
  int XL = 0xFF & int(c.r * 255.);
  int YH = 0xFF & int(c.g * 255.);
  int YL = 0xFF & int(c.b * 255.);
  int Xb = XH << 8 | XL;
  int Yb = YH << 8 | YL;

  float fx = toFloat(Xb);
  float fy = toFloat(Yb);
  return vec2(fx,fy);
}

//  decode color (vec4) into 'float'
//  (low-level), **DO NOT CHANGE**
//
float decode(vec4 c) {
  int R = 0xFF & int(c.r * 255.);
  int G = 0xFF & int(c.g * 255.);
  int B = 0xFF & int(c.b * 255.);
  int A = 0xFF & int(c.a * 255.);
  int result = A<<24 | R<<16 | G<<8 | B;
  return intBitsToFloat(result);
}

//  encode vec2 (2x float) into color (vec4) using HALF-precision
//  (low-level), **DO NOT CHANGE**
//
vec4 encodeV2(vec2 f) {
  int IX = fromFloat(f.x);
  int IY = fromFloat(f.y);
  int A = (IX >> 8) & 0xFF;
  int R = IX & 0xFF;
  int G = (IY >> 8) & 0xFF;
  int B = IY & 0xFF;
  return vec4(float(R),float(G),float(B),float(A))/255.;  
}

//  encode float into color (vec4)
//  (low-level), **DO NOT CHANGE**
//
vec4 encode(float f) {
  int i = floatBitsToInt(f);  
  int A = (i >> 24) & 0xFF;
  int R = (i >> 16) & 0xFF;
  int G = (i >> 8)  & 0xFF;
  int B = i & 0xFF;
  return vec4(float(R),float(G),float(B),float(A))/255.;
}

//
//  Compute new Dot's acceleration
//
void main() {

  vec2 st    = gl_FragCoord.xy / u_resolution.xy;

  //  computation reject
  int  x = int(gl_FragCoord.x);  
  int  y = int(u_resolution.y - gl_FragCoord.y);  
  if (x + y * int(u_resolution.x) >= u_numDots) {
    gl_FragColor = encodeV2(vec2(10.0, 10.0));
    return;
  }  
  
  vec4 cPos  = texture2D(u_pos, vec2(st.x, 1.0 - st.y));
  vec2 pos = decodeV2(cPos);
  vec2 acc = vec2(0.0,0.0);

  float Epsilon = 0.0000001;


  //  Force from the underlying field
  //
  int simXY_2 = u_simXY / 2;
  vec2 uv_res = vec2(float(u_simXY));
  
  for (int y = 0; y < u_simXY; y++) {
    for (int x = 0; x < u_simXY; x++) {
      
      // Compute the position of target pixel 
      vec2 bmpXY;
      bmpXY.x = float(x - simXY_2)/float(simXY_2);
      bmpXY.y = float(y - simXY_2)/float(simXY_2);
        
      vec2 uv = vec2(float(x)+0.5, float(y)+0.5) / uv_res;      
      vec4 cQ = texture2D(u_bmpQ, vec2(uv.x, uv.y));
      float bmpQ = decode(cQ);
            
      //  Periodic boundary
      vec2 dp = bmpXY - pos;
      if (dp.x > 1.0) dp.x -= 2.0;
      else if (dp.x < -1.0) dp.x += 2.0;
      if (dp.y > 1.0) dp.y -= 2.0;
      else if (dp.y < -1.0) dp.y += 2.0;      
      
      float d2 = dot(dp, dp) + 0.00003;  // Super Sharp
      float d  = sqrt(d2);
      
      if (abs(d - 0.0) > Epsilon) {
        float q = bmpQ / d2;
        acc += q * dp / d;
      }      
      
    }
  }

  
  //  inter-free Dots
  for (int i = 0; i < u_numDots; i++) {

    int x = i % int(u_resolution.x);
    int y = i / int(u_resolution.x);
    vec2 uv = vec2(float(x)+0.5, float(y)+0.5) / u_resolution.xy;

    if (uv == st) continue; // skip oneself
    
    vec4 cDotPos = texture2D(u_pos, vec2(uv.x, uv.y));
    vec2 dotPos = decodeV2(cDotPos);
    
    vec2 dp = dotPos - pos;

    //if (dp.x > 1.0) dp.x -= 2.0;
    //else if (dp.x < -1.0) dp.x += 2.0;
    //if (dp.y > 1.0) dp.y -= 2.0;
    //else if (dp.y < -1.0) dp.y += 2.0;

    float d2 = dot(dp, dp) + 0.00003;
    float d  = sqrt(d2);

    if (abs(d - 0.0) > Epsilon) {
      float q = u_dotCharge / d2;
      acc -= q * dp / d;
    }
    
  }    

  acc *= u_dotCharge;
  gl_FragColor = encodeV2(acc);  // Results to be rec'd by Active 'accBuf'

}
