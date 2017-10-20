#!/usr/bin/perl -w

use strict;
use FindBin qw($Bin);
use File::Path;
use File::Spec;
use File::Basename;
use Getopt::Long;

my $sliceDim = 2;
my $slicePosition="45%";
my @contrastRangeDefault = ("0%", "99.9%");
my $useGlobalContrast = 0;
my $stretchContrast = 0;
my $flipAxes="n";
my $pim = "fq";
my $mask="";
# By default, set the slice position from mask centroid (if we have a mask)
# This set to 0 if --slice is present
my $setSlicePositionFromMask=1; 

my $usage = qq{

  $0  
      --input
      --output
      [ options ]

  Required args:

   --input  
     Either a 4D image or a series of 3D images. If 3D, they are assumed to be spatially aligned.

   --output
     Output file, should end with .nii or .nii.gz. If the input is 3D, a list of slices and associated image files
     is also written.

  Options:

   --axis
     Slice along axis 0 = x, 1 = y, 2 = z. This slices in the voxel space (default = $sliceDim).

   --slice
     Slice number, from 0 to [number of slices] - 1, or a percentage (default = ${slicePosition}, or centroid of the mask).

   --flip
     Flip the slices, n(ot at all), or in x, y, or xy (default = $flipAxes).
 
   --mask 
     Mask image to be applied to the data before slicing. Also allows automatic slicing, if --slice is not specified, 
     the mask centroid is used to determine the slice location.
  
   --contrast-range 
     Contrast can be clipped either be by percentiles or a fixed range (default = "$contrastRangeDefault[0] $contrastRangeDefault[1]"). 
     If a percentile, the contrast will be adjusted individually for each slice, override this with "--use-global-contrast 1".
     If contrast is based on quantiles (see --percent-intensity-mode), the upper contrast range cannot include 100%, as this 
     causes a rounding error in c3d. 

   --use-global-contrast
     Specifies whether a fixed intensity range will be defined by the contrast-range percentiles in the first 
     volume, and applied to all volumes. Has no effect if the specified contrast range is absolute values (default = $useGlobalContrast).

   --stretch-contrast
     If 1, the intensities in the slice are mapped linearly to a 16-bit integer range. This is useful if you want similar contrast
     across slices, for example to visualize DWI measurements at different b-values (default = $stretchContrast).

   --percent-intensity-mode 
     Sets c3d's percent intensity mode. Use "q" for quantile, "fq" for foreground quantile (excluding voxels with 0 intensity) or "r" 
     to use percentages of the intensity range without regard to quantiles (default = fq).


  Requires: ANTs (for 4D input only), c3d.

  Changing dimensionality involves a loss of orientation information. If you need the slices to be oriented a particular 
  way (eg anatomical right on screen left), check output carefully. 



};

if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 1;
}


my @inputImages;
my $outputFile;
my @contrastRange;

GetOptions ("input=s{1,1000}" => \@inputImages,
	    "output=s" => \$outputFile,
	    "axis=i" => \$sliceDim,
	    "contrast-range=s{2}" => \@contrastRange,	    
	    "flip=s" => \$flipAxes,
	    "mask=s" => \$mask,
	    "percent-intensity-mode=s" => \$pim,
	    "slice=s" => sub { $slicePosition = $_[1]; $setSlicePositionFromMask = 0;},
	    "stretch-contrast=s" => \$stretchContrast,
	    "use-global-contrast=i" => \$useGlobalContrast
    )
    or die("Error in command line arguments\n");

@contrastRange = @contrastRangeDefault unless @contrastRange;

# print "$contrastRange[0] $contrastRange[1] \n "; exit 1;

my $c3dExe = `which c3d`;
my $antsExe = `which ExtractSliceFromImage`;

chomp($c3dExe, $antsExe);

(-f $c3dExe) || die("\nMissing required program: c3d\n");

# Use ANTs to slice 4D images, as it works the same way with 4D or 5D input
if (scalar(@inputImages) == 1) {
    (-f $antsExe) || die("\nMissing required program: ExtractSliceFromImage (part of ANTs)\n");
}

if ( $setSlicePositionFromMask && -f $mask ) {

    my $maskCentroid =`c3d $mask -dup -centroid`;
    
    # Assuming here that it will be a positive number with no exponent
    $maskCentroid =~ m/CENTROID_VOX \[([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+)\]/;
	
    my @centroidSlices = ($1, $2, $3);
    
    $slicePosition = $centroidSlices[$sliceDim];
}

if ($useGlobalContrast && ($contrastRange[0] =~ m/%/ || $contrastRange[1] =~ m/%/)) {
    my $info = `c3d -pim $pim $inputImages[0] -clip $contrastRange[0] $contrastRange[1] -info`;

    $info =~ m/range = \[([0-9.e-]+), ([0-9.e-]+)\];/;

    @contrastRange = ($1, $2);

    print "Setting contrast range from \n $info \n";
}

# Resolve slice percentage into a number for ANTs
if ($slicePosition =~ m/%/) {
    my $info = `c3d $inputImages[0] -info`;

    $info =~ m/dim = \[([0-9]+), ([0-9]+), ([0-9]+)\];/;

    my @dims = ($1, $2, $3);

    my $numSlices = $dims[$sliceDim];

    my $fraction = $slicePosition;

    $fraction =~ s/%//;

    $fraction = $fraction / 100.0;
    
    $slicePosition = int( ($numSlices - 1) * $fraction);

}

my $inputFileRoot = fileparse($inputImages[0]);

$inputFileRoot =~ s/\.nii(\.gz)?//;

my $sysTmpDir = $ENV{'TMPDIR'} || "/tmp";

my $tmpDir = "${sysTmpDir}/${inputFileRoot}";

mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir (maybe it exists from a previous failed run)\n\t";


my $flipCmd = "";

if (!($flipAxes eq "n")) {
    $flipCmd = " -flip $flipAxes ";
}

# Apply this after contrast is clipped
my $contrastCmd = " -clip $contrastRange[0] $contrastRange[1] ";

if ($stretchContrast) {
    $contrastCmd = "$contrastCmd -pim range -stretch 0% 100% 0 65534 -pim $pim ";
}

if (scalar(@inputImages) == 1) {

    # single 4D input volume
    
    my $sliceImage = "${tmpDir}/slicesStacked.nii.gz";

    # Get the same slice from each volume, and output as a single 3D image
    system("ExtractSliceFromImage 4 $inputImages[0] $sliceImage $sliceDim $slicePosition");

    if (-f $mask) {
	my $maskSliceLetter = "z";
	
	if ($sliceDim == 0) {
	    $maskSliceLetter="x";
	}
	elsif ($sliceDim == 1) {
	    $maskSliceLetter="y";
	}
	
        system("c3d -pim $pim $mask -slice $maskSliceLetter $slicePosition -popas mask $sliceImage -slice z 0:100% -foreach -as theSlice -push mask -copy-transform -push theSlice -multiply $contrastCmd $flipCmd -endfor -tile z -o ${outputFile}");

    }    
    else {
	
	system("c3d -pim $pim $sliceImage -slice z 0:100% -foreach $contrastCmd $flipCmd -endfor -tile z -o ${outputFile}");

    }

}
else {

    my $outputRoot = $outputFile;

    $outputRoot =~ s/\.nii(\.gz)?//;

    open(SLICEINFO, ">${outputRoot}.csv");

    print SLICEINFO "SliceNumber,Image\n";

    # 3D images sliced by c3d, requires x / y / z
    my $sliceLetter = "z";

    if ($sliceDim == 0) {
	$sliceLetter="x";
    }
    elsif ($sliceDim == 1) {
	$sliceLetter="y";
    }

    # Create slices from input volumes
    my $maskCmd = "";

    if (-f $mask ) {
	$maskCmd = " $mask -multiply ";
    }

    my $sliceCounter = 1;

    foreach my $input3D (@inputImages) {

	system("c3d -pim $pim $input3D $maskCmd -slice $sliceLetter $slicePosition $contrastCmd -o ${tmpDir}/sliceContrastFix_" . sprintf("%03d", ${sliceCounter}) . ".nii.gz");

	print SLICEINFO "${sliceCounter},$input3D\n";
	
	$sliceCounter++;
    }

    
    my @slices = `ls ${tmpDir}/sliceContrastFix_*.nii.gz`;
    
    chomp(@slices);

    system("c3d " . join(" ", @slices) . " -foreach $flipCmd -endfor -tile z -o $outputFile ");
    
    close(SLICEINFO);

}

system("rm $tmpDir/*");
system("rmdir $tmpDir");
