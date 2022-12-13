#!/bin/bash
set -euo pipefail

# Default values that can be overriden when calling this script

# TODO figure out the path on windows.
: "${FFMPEG:=/c/Users/kixel/Videos/VBR/ffmpeg/bin/ffmpeg.exe}"

# The input file. TODO use a relative path.
: "${INPUT:=/c/Users/kixel/Videos/Demo/10games.avi}"

# TODO support vmaf when the resolution is not the same as the input file.
: "${RESOLUTION:=1920x1080}"

# The number of frames per second.
: "${FPS:=60}"

# The preset, defaulting to the nvenc P6
: "${PRESET:=p6}"

# The max bitrate in Mb/s
: "${BITRATE:=6}"

# The GoP duration in seconds
: "${GOP:=2}"

# Set to 1 to generate CBR as reference
: "${CBR:=1}"

# Set to the minimum and maximum CQ values
: "${CQ_MIN:=24}"
: "${CQ_MAX:=40}"

# Generate a single rindition using the provided CQ
generate() {
	CQ="$1"
	OUTPUT="${RESOLUTION}-${FPS}-${PRESET}-${BITRATE}M"
	
	# Disable stdout
	FLAGS=" -hide_banner -loglevel error"
	
	# Yes to overriding files
	FLAGS+=" -y"
	
	# Input file
	FLAGS+=" -i ${INPUT}"
	
	# Use NVENC
	FLAGS+=" -c:v h264_nvenc"
	
	# No audio
	FLAGS+=" -an"
	
	# Use the provided preset
	FLAGS+=" -preset ${PRESET}"
	
	# Scale to the provided resolution
	FLAGS+=" -s:v ${RESOLUTION}"
	
	# Use the provided FPS
	FLAGS+=" -f:v fps=${FPS}"
	
	# Make sure we're using YUV
	#FLAGS+=" -pix_fmt yuv420p"
	
	# Enable AQ, which is default in OBS for some reason
	#FLAGS+=" -spatial-aq 1 -temporal-aq 1 -aq-strength 7"

	if [ "$CQ" -eq "0" ]; then
		# CBR mode
		FLAGS+=" -rc:v cbr"
		
		# Use the provided bitrate
		FLAGS+=" -b:v ${BITRATE}M"
		
		OUTPUT+="-cbr"
	else
		# VBR mode
		FLAGS+=" -rc:v vbr"
		
		# Use the provided CQ value
		FLAGS+=" -cq ${CQ}"
		
		# Set the max bitrate to cap VBR
		FLAGS+=" -maxrate ${BITRATE}M"
		
		OUTPUT+="-vbr-cq${CQ}"
	fi
	
	# Create a GOP every 2s
	FLAGS+=" -g $(( FPS*GOP ))"
	
	# Average the max bitrate over the entire GoP
	FLAGS+=" -bufsize $(( BITRATE*GOP ))M"
	
	# Output to MP4
	FLAGS+=" -f mp4 ${OUTPUT}.mp4"
	
	# Run FFMPEG with these flags to generate the file
	$FFMPEG $FLAGS
	
	# Disable stdout
	FLAGS=" -hide_banner -loglevel error"
	
	# The distorted input file
	FLAGS+=" -i ${OUTPUT}.mp4"
	
	# The reference input file
	FLAGS+=" -i ${INPUT}"
	
	# Use libvmaf to generate VMAF and PSNR scores
	FLAGS+=" -lavfi [0][1]libvmaf=log_path=${OUTPUT}.json:log_fmt=json:psnr=1:n_threads=4"
	
	# Don't output any files
	FLAGS+=" -f null -"
	
	# Run FFMPEG with these flags to analyze the file
	$FFMPEG $FLAGS
	
	# Parse the produced file to get the results
	RESULT_VMAF=$( jq -r .pooled_metrics.vmaf.mean < "${OUTPUT}.json" )
	RESULT_PSNR=$( jq -r .pooled_metrics.psnr_y.mean < "${OUTPUT}.json" ) 
	RESULT_SIZE=$( stat -c%s "${OUTPUT}.mp4" )
	
	# Echo the results in CSV format
	echo "${RESOLUTION},${FPS},${GOP},${PRESET},${BITRATE}M,${CQ},${RESULT_SIZE},${RESULT_PSNR},${RESULT_VMAF}"
}

# Echo the header in CSV
echo "resolution,fps,gop,preset,max bitrate,cq,size,psnr,vmaf"

if [ "$CBR" -eq "1" ]; then
	# CBR
	generate 0
fi

# Loop over all of hte CQ values
for CQ in $( seq $CQ_MIN $CQ_MAX ); do
	# VBR
	generate "${CQ}"
done
