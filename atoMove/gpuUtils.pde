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

//  Decodes a Processing 'color' to float
float decode(color c) {
  Long l = Long.parseLong(hex(c), 16);
  return Float.intBitsToFloat(l.intValue());
} 

//  Encodes a float into Processing 'color'
color encode(float f) {
  return unhex(hex(Float.floatToRawIntBits(f)));
}

//  Decodes a Processing 'color' to Float2
Float2 decodeF2(color c) {
  
  Long l = Long.parseLong(hex(c), 16);
  int rawBits = l.intValue();
  
  int rawX = (rawBits >> 16) & 0xFFFF;
  float x = toFloat(rawX);
  int rawY = rawBits & 0xFFFF;
  float y = toFloat(rawY);
  
  Float2 result = new Float2(x,y);
  return result;
}

//  Encodes Float2 into a Processing 'color', *Precision halved*
color encodeF2(Float2 f) {
  int rawX = fromFloat(f.x);
  int rawY = fromFloat(f.y);
  int rawBits = (rawX << 16) & 0xFFFF0000 | rawY;
  return unhex(hex(rawBits));  
}

//  Basic Class for 2 floats
class Float2{
  float x,y;
  Float2(float _x, float _y) {
    x = _x;
    y = _y;
  }
}


//
//  Code from stackoverflow for Half precision floating point numbers in Java
//  https://stackoverflow.com/questions/6162651/half-precision-floating-point-in-java
//

// ...........................................................
// ignores the higher 16 bits
public static float toFloat( int hbits )
{
    int mant = hbits & 0x03ff;            // 10 bits mantissa
    int exp =  hbits & 0x7c00;            // 5 bits exponent
    if( exp == 0x7c00 )                   // NaN/Inf
        exp = 0x3fc00;                    // -> NaN/Inf
    else if( exp != 0 )                   // normalized value
    {
        exp += 0x1c000;                   // exp - 15 + 127
        if( mant == 0 && exp > 0x1c400 )  // smooth transition
            return Float.intBitsToFloat( ( hbits & 0x8000 ) << 16
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
    return Float.intBitsToFloat(          // combine all parts
        ( hbits & 0x8000 ) << 16          // sign  << ( 31 - 15 )
        | ( exp | mant ) << 13 );         // value << ( 23 - 10 )
}

// returns all higher 16 bits as 0 for all results
public static int fromFloat( float fval )
{
    int fbits = Float.floatToIntBits( fval );
    int sign = fbits >>> 16 & 0x8000;          // sign only
    int val = ( fbits & 0x7fffffff ) + 0x1000; // rounded value

    if( val >= 0x47800000 )               // might be or become NaN/Inf
    {                                     // avoid Inf due to rounding
        if( ( fbits & 0x7fffffff ) >= 0x47800000 )
        {                                 // is or must become NaN/Inf
            if( val < 0x7f800000 )        // was value but too large
                return sign | 0x7c00;     // make it +/-Inf
            return sign | 0x7c00 |        // remains +/-Inf or NaN
                ( fbits & 0x007fffff ) >>> 13; // keep NaN (and Inf) bits
        }
        return sign | 0x7bff;             // unrounded not quite Inf
    }
    if( val >= 0x38800000 )               // remains normalized value
        return sign | val - 0x38000000 >>> 13; // exp - 127 + 15
    if( val < 0x33000000 )                // too small for subnormal
        return sign;                      // becomes +/-0
    val = ( fbits & 0x7fffffff ) >>> 23;  // tmp exp for subnormal calc
    return sign | ( ( fbits & 0x7fffff | 0x800000 ) // add subnormal bit
         + ( 0x800000 >>> val - 102 )     // round depending on cut off
      >>> 126 - val );   // div by 2^(1-(exp-127+15)) and >> 13 | exp=0
}
