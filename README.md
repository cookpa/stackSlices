Scripts using ANTs and c3d to extract slices from series of 4D or 3D volumes, adjust contrast, and make animations with ImageMagick.


## stackSlices.pl

Main features

 * Images can be masked before slicing.

 * Slice placement as a number, percentage, or mask centroid.

 * Contrast can be adjusted for each slice individually or globally.

 * Contrast can be stretched to equalize intensities, useful for visual inspection of DWI.

 * Slices can be flipped in x or y as needed.

 * Input can be a 4D image or a series of 3D images. If the latter, a CSV file linking slice to input volume is also output.


## animateSliceStack.pl

The animation part takes as input a stack of slices in NIFTI format, and produces an animation such as a .gif using ImageMagick.

One use of this is to quickly assess the overall amount of motion and eddy current distortion in DWI. 