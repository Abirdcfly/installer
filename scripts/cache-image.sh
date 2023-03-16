#!/usr/bin/env bash
#
# Copyright contributors to the Hyperledger Fabric Operator project
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
# 	  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
export UPLOAD_IMAGE=NO
function save_all_images() {
	outputDir=$1
	imageListFile=$2
	if [ ! -f $imageListFile ]; then
		echo "" >$imageListFile
	fi
	echo "get all images list..."
	IMAGES=$(kubectl get po -A -o yaml | grep "image: " | awk -F ": " '{print $2}' | sort -u)
	echo "compare all images list with $imageListFile"
	same=0
	echo $IMAGES | diff - $imageListFile -y -q && same=0 || same=1
	if [[ $same -eq 0 ]]; then
		echo "image list is same with cache, skip store. done.✅"
	else
		echo "try to save all cluster images to $outputDir, images list to $imageListFile..."
		echo $IMAGES >$imageListFile
		dockerContainerNames=$(kubectl get node --no-headers=true | awk '{print $1}')
		for dockerContainerName in ${dockerContainerNames[@]}; do
			echo "$dockerContainerName image list:"
			docker exec -i ${dockerContainerName} ctr --namespace=k8s.io images list
		done
		n=0
		for image in ${IMAGES[@]}; do
			n=$((n + 1))
			for dockerContainerName in ${dockerContainerNames[@]}; do
				docker exec -i ${dockerContainerName} ctr --namespace=k8s.io images export --all-platforms ${outputDir}/${n} ${image} || exit_status=$?
				if [[ $exit_status -eq 0 ]]; then
					break
				elif [ $exit_status -eq 1 ]; then
					echo "$dockerContainerName has no image $image"
				fi
			done
		done
		UPLOAD_IMAGE=YES
		echo "save all images done.✅"
	fi
	export UPLOAD_IMAGE=$UPLOAD_IMAGE
}

function load_all_images() {
	kindName=$1
	inputDir=$2
	if [ ! -d $inputDir ]; then
		echo "no image dir found $inputDir, skip"
		exit 0
	fi
	if [ ! -n "$(ls $inputDir)" ]; then
		echo "no image found in $inputDir, skip"
		exit 0
	fi
	echo "try to load all cluster images from $outputDir to kind cluster $kindName..."
	dockerContainerNames=$(docker ps -a --filter label=io.x-k8s.kind.cluster=${kindName} --format {{.Names}})
	for dockerContainerName in ${dockerContainerNames[@]}; do
		for imagefile in "$inputDir"/*; do
			docker exec --privileged -i ${dockerContainerName} ctr --namespace=k8s.io images import ${imagefile}
		done
		echo "load all images for ${dockerContainerName} done."
	done
	echo "load all images done.✅"
}
