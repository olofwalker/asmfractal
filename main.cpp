#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <array>
#include <string.h>

class rgb {
public:
    rgb(double _r,double _g, double _b) : r(_r),g(_g),b(_b) {};
    rgb() : r(0),g(0),b(0) {};

    double r;       // percent
    double g;       // percent
    double b;       // percent
};

typedef struct {
    double h;       // angle in degrees
    double s;       // percent
    double v;       // percent
} hsv;

static hsv   rgb2hsv(rgb in);
static rgb   hsv2rgb(hsv in);

hsv rgb2hsv(rgb in)
{
    hsv         out;
    double      min, max, delta;

    min = in.r < in.g ? in.r : in.g;
    min = min  < in.b ? min  : in.b;

    max = in.r > in.g ? in.r : in.g;
    max = max  > in.b ? max  : in.b;

    out.v = max;                                // v
    delta = max - min;
    if (delta < 0.00001)
    {
        out.s = 0;
        out.h = 0; // undefined, maybe nan?
        return out;
    }
    if( max > 0.0 ) { // NOTE: if Max is == 0, this divide would cause a crash
        out.s = (delta / max);                  // s
    } else {
        // if max is 0, then r = g = b = 0
            // s = 0, v is undefined
        out.s = 0.0;
        out.h = NAN;                            // its now undefined
        return out;
    }
    if( in.r >= max )                           // > is bogus, just keeps compilor happy
        out.h = ( in.g - in.b ) / delta;        // between yellow & magenta
    else
    if( in.g >= max )
        out.h = 2.0 + ( in.b - in.r ) / delta;  // between cyan & yellow
    else
        out.h = 4.0 + ( in.r - in.g ) / delta;  // between magenta & cyan

    out.h *= 60.0;                              // degrees

    if( out.h < 0.0 )
        out.h += 360.0;

    return out;
}


rgb hsv2rgb(hsv in)
{
    double      hh, p, q, t, ff;
    long        i;
    rgb         out;

    if(in.s <= 0.0) {       // < is bogus, just shuts up warnings
        out.r = in.v;
        out.g = in.v;
        out.b = in.v;
        return out;
    }
    hh = in.h;
    if(hh >= 360.0) hh = 0.0;
    hh /= 60.0;
    i = (long)hh;
    ff = hh - i;
    p = in.v * (1.0 - in.s);
    q = in.v * (1.0 - (in.s * ff));
    t = in.v * (1.0 - (in.s * (1.0 - ff)));

    switch(i) {
    case 0:
        out.r = in.v;
        out.g = t;
        out.b = p;
        break;
    case 1:
        out.r = q;
        out.g = in.v;
        out.b = p;
        break;
    case 2:
        out.r = p;
        out.g = in.v;
        out.b = t;
        break;

    case 3:
        out.r = p;
        out.g = q;
        out.b = in.v;
        break;
    case 4:
        out.r = t;
        out.g = p;
        out.b = in.v;
        break;
    case 5:
    default:
        out.r = in.v;
        out.g = p;
        out.b = q;
        break;
    }
    return out;
}

void color(int red, int green, int blue)
{
    fputc((char)red, stdout);
    fputc((char)green, stdout);
    fputc((char)blue, stdout);
}

double lerp(const double start, const double end, const double t)
{
    return (1.0 - t)  * start + t * end;
}

std::array<rgb,2> colors = {
    rgb(0.0, 0.0, 255.0),
    rgb(204.0, 218.0,  255.0)
};

int main(int argc, char *argv[])
{
    char str[1024];
    FILE *f = fopen("/home/rwalker/develop/fractal/data.txt","w+");
    int iterations = 1024;
    double slots = iterations / (colors.size()-1);
    for(int p=0;p<colors.size()-1;p++)
    {
        rgb a = colors[p];
        rgb b = colors[p+1];
        for(double e=0;e<slots;e++)
        {
            double t = e/slots;
            rgb final;
            final.r = lerp(a.r,b.r,t);
            final.g = lerp(a.g,b.g,t);
            final.b = lerp(a.b,b.b,t);
            sprintf(str,"db %d, %d, %d, 0\n",static_cast<int>(ceil(final.r)),static_cast<int>(ceil(final.g)),static_cast<int>(ceil(final.b)));
            fwrite(str,1,strlen(str),f);
    //        printf("dq %.2f, %.2f, %.2f, %.2f, 0\n",e,final.r,final.g,final.b);
        }
    }
    fclose(f);
    return 0;
}
