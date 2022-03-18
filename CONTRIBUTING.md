# tl;dr: `git clone --single-branch https://github.com/tianon/docker-brew-ubuntu-core.git`

Please do not open pull requests to update images. We're super happy to get PRs
for anything else other than updating the packages in an image though!

# Scripts to prepare updates to the Ubuntu official Docker images

The process for updating the images goes like this:

1. Tarballs are published at https://partner-images.canonical.com/oci/ by
   Canonical

2. Someone with appropriate permissions runs the
   https://github.com/tianon/docker-brew-ubuntu-core/actions/workflows/update-branches.yml
   workflow.

3. This updates each `arch-*` branch of
   https://github.com/tianon/docker-brew-ubuntu-core/ to be one commit ahead of
   master, that commit adding tarballs/Dockerfiles/manifests/checksums for each
   supported release of Ubuntu (this is why you pass `--single-branch` to clone
   to get this repo, you don't want to be downloading all these tarballs)

4. `generate-stackbrew-library.sh` from this repo is run on a developer machine
   to produce a replacement for
   https://github.com/docker-library/official-images/blob/master/library/ubuntu

5. This replacement is proposed as a PR to
   https://github.com/docker-library/official-images

6. The PR is reviewed, approved and submitted by the official image maintainers
   (https://github.com/docker-library/official-images/blob/master/MAINTAINERS)

7. Some Jenkins happens

8. The new images are published on https://hub.docker.com

Please feel free to open issues and discuss these images.  You can submit pull
requests to update the scripts and image metadata, but submitting pull requests
to the `arch-*` branches to update the images does not work and only upsets the
pig, or something like that.
