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
uniform sampler2D u_vel;
uniform sampler2D u_a0;
uniform sampler2D u_a1;

uniform float u_vMax;
uniform float u_sustain;
uniform float u_dt_2;
uniform int u_numDots;

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
//  Compute new Dot's velocity
//
void main() {

  vec2 st = gl_FragCoord.xy / u_resolution.xy;
  
  //  computation reject
  int  x = int(gl_FragCoord.x); 
  int  y = int(u_resolution.y - gl_FragCoord.y);  
  if (x + y * int(u_resolution.x) >= u_numDots) {
    gl_FragColor = encodeV2(vec2(10.0, 10.0));
    return;
  }    
  
  vec4 cV0  = texture2D(u_vel, vec2(st.x, 1.0 - st.y));   // OLD Vel
  vec4 cA0  = texture2D( u_a0, vec2(st.x, 1.0 - st.y));   // OLD Acc
  vec4 cA1  = texture2D( u_a1, vec2(st.x, 1.0 - st.y));   // NEW Acc

  vec2 v0   = decodeV2(cV0);
  vec2 a0   = decodeV2(cA0);
  vec2 a1   = decodeV2(cA1);

  //  Update velocity with averaged Acc
  vec2  vel = (u_sustain * v0) + (u_dt_2 * (a0 + a1));
  float len = length(vel);
  if (len > u_vMax) vel *= (u_vMax/len);
  
  gl_FragColor = encodeV2(vel);    // Results to be rec'd by 'velBuf'

}
