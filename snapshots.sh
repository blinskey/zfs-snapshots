#!/bin/sh

# Copyright (c) 2025 Benjamin Linskey <contact@linskey.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# snapshots.sh -- Manages ZFS snapshots.
#
# At least one of the following options must be provided to specify an
# operation to perform:
#
#	-c	create snapshot(s)
#	-p	prune snapshots
#	-l	list snapshots
#
# If the -c or -p option is specified, at least one dataset must be specified
# as well.
#
# If the -r option is specified, child datasets of the specified dataset(s)
# will be recursively created, deleted, or listed.
#
# If the -c or -p option is specified, the -t option must be provided to
# specify a tag.
#
# If the -p option is specified, the -k option must be provided to specify the
# number of snapshots to keep for each dataset (including any newly created
# snapshots).
#
# Usage: snapshots.sh [-cplrnvh] [-t tag] [-k num] [dataset ...]"
#
#	-c			create snapshot(s) (requires -t)
#	-p			prune snapshots (requires -t and -k)
#	-l			list snapshots
#	-r			recursively create or delete snapshots
#	-n			dry run: print commands that would be executed, but do not
#				actually modify data
#	-v			verbose mode
#	-h			print usage
#	-k num		keep *num* snapshots for each dataset, including any newly
#				created snapshots
#	-t tag		use *tag* as the snapshot name prefix

set -e

usage() {
	printf "usage: %s [-cplrnvh] [-t tag] [-k num] [dataset ...]\n" "$0"
}

tag=
keep=
recursive=
dry_run=
verbose=
create=
prune=
list=

while getopts t:k:cplrknvh name; do
	case $name in
		t)	tag="$OPTARG";;
		k)	keep="$OPTARG";;
		c)	create=1;;
		p)	prune=1;;
		l)	list=1;;
		r)	recursive=1;;
		n)	dry_run=1;;
		v)	verbose=1;;
		h)	usage
			exit 0;;
		?)	usage
			exit 2;;
	esac
done
shift $((OPTIND - 1))

if [ -z "$create" ] && [ -z "$prune" ] && [ -z "$list" ]; then
	printf "At least one of -c, -p, and -l must be specified.\n"
	usage
	exit 1
fi

if [ "$#" -eq 0 ] && { [ -n "$create" ] || [ -n "$prune" ]; }; then
	printf "At least one dataset must be specified\n"
	usage
	exit 1
fi

if { [ -n "$create" ] || [ -n "$prune" ]; } && [ -z "$tag" ]; then
	printf "Missing -t option\n"
	usage
	exit 1
fi

if [ -n "$prune" ] && [ -z "$keep" ]; then
	printf "Missing -k option\n"
	usage
	exit 1
fi

if [ -z "$prune" ] && [ -n "$keep" ]; then
	printf "\-k option is only valid with -p\n"
	usage
	exit 1
fi

create_cmd='zfs snapshot'
if [ -n "$recursive" ]; then
	create_cmd="$create_cmd -r"
fi
readonly create_cmd

destroy_cmd='zfs destroy'
if [ -n "$recursive" ]; then
	destroy_cmd="$destroy_cmd -R"
fi
readonly destroy_cmd

# Create snapshots.
if [ -n "$create" ]; then
	for dataset in "$@"; do
		# FreeBSD's date -I option uses a "+00:00" suffix rather than "Z", and
		# the + character is illegal in snapshot names, so we have to specify
		# the format manually.
		cmd="$create_cmd ${dataset}@${tag}-$(date -z utc +%Y-%m-%dT%H:%M:%SZ)"

		if [ -n "$dry_run" ] || [ -n "$verbose" ]; then
			printf "%s\n" "$cmd"
		fi

		if [ -z "$dry_run" ]; then
			$cmd
		fi
	done
fi

# Prune snapshots.
if [ -n "$prune" ]; then
	if [ -n "$prune_only" ]; then
		keep=$((keep + 1))
	fi

	for dataset in "$@"; do
		snapshots=$(zfs list -t snapshot -o name -S name -H "$dataset")
		to_delete=$(printf "%s\n" "$snapshots" | grep "@${tag}-" | tail -n +"$((keep + 1))")
		for s in $to_delete; do
			cmd="$destroy_cmd $s"
			if [ -n "$dry_run" ] || [ -n "$verbose" ]; then
				printf "%s\n" "$cmd"
			fi

			if [ -z "$dry_run" ]; then
				$cmd
			fi
		done
	done
fi

# List snapshots.
if [ -n "$list" ]; then
	cmd="zfs list"
	if [ -n "$recursive" ]; then
		cmd="$cmd -r"
	fi
	snapshots=$($cmd -t snapshot -o name -s name -H "$@")

	if [ -n "$tag" ]; then
		printf "%s\n" "$snapshots" | grep "@${tag}-"
	else
		printf "%s\n" "$snapshots"
	fi
fi
