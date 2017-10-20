#!/usr/bin/perl -w

use strict;
use FindBin qw($Bin);
use File::Path;
use File::Spec;
use File::Basename;
use Getopt::Long;

my $cropPercent = 90;
my $delay = 30;
my $flipAxes="n";
my $gifWindowSize=700;


my $usage = qq{

  $0  
      --input
      --output
      [ options ]

  Required args:

   --input  
     A 3D NIFTI image containing a stack of slices, as produced by stackSlices.pl.

   --output
     Output file, should end with .gif, .avi, or other ImageMagick movie format.

  Options:


   --crop
     Crop window, as a percentage of the original slice area (default = $cropPercent). The cropped slices
     are scaled to the frame size of the output.

   --frame-duration
     Animation frame duration, in 100ths of a second (default = $delay).

   --flip
     Flip the slices, n(ot at all), or in x, y, or xy (default = $flipAxes). Even if the input slices are correctly 
     oriented, this may be necessary to undo flipping that occurs during conversion.
 
   --animation-frame-size
     Size of GIF output frame, in pixels. If the slice is not square, the longer axis is scaled to this value 
     (default = $gifWindowSize).


  Requires: c3d, ImageMagick. 

};

if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 1;
}

my ($inputImage, $outputFile);


GetOptions ("input=s" => \$inputImage,
	    "output=s" => \$outputFile,
	    "animation-frame-size=i" => \$gifWindowSize,
	    "flip=s" => \$flipAxes,
	    "frame-duration=i" => \$delay	    
    )
    or die("Error in command line arguments\n");


my $c3dExe = `which c3d`;
my $imageMagickExe = `which convert`;

chomp($c3dExe, $imageMagickExe);

(-f $c3dExe) || die("\nMissing required program: c3d\n");
(-f $imageMagickExe) || die("\nMissing required program: convert (part of ImageMagick)\n");

my $inputFileRoot = fileparse($inputImage);

$inputFileRoot =~ s/\.nii(\.gz)?//;

my $sysTmpDir = $ENV{'TMPDIR'} || "/tmp";

my $tmpDir = "${sysTmpDir}/${inputFileRoot}";

mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir (maybe it exists from a previous failed run)\n\t";

system("c3d -pim range $inputImage -slice z 0:100% -foreach -stretch 0% 100% 0 65534 -clip 0 65534 -endfor -type ushort -oo ${tmpDir}/sliceUShort_%03d.png");

my @slices = `ls ${tmpDir}/sliceUShort_*.png`;

chomp(@slices);

# Crop background
foreach my $png (@slices) {
    system("convert $png -gravity Center -crop ${cropPercent}x${cropPercent}%+0+0 +repage $png");
}

# Determine flip operation
my $flipCmd="";

if ($flipAxes eq "x") {
    $flipCmd = "-flop";
}
elsif ($flipAxes eq "y") {
    $flipCmd = "-flip";
}
elsif ($flipAxes eq "xy") {
    $flipCmd = "-flip -flop";
}
    
system("convert -delay $delay -loop 0 -gravity Center -scale ${gifWindowSize}x${gifWindowSize} $flipCmd " . join(" ", @slices) . " ${outputFile}");

system("rm $tmpDir/*");
system("rmdir $tmpDir");
