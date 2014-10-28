#!/usr/bin/perl

## generate impute2 jobs for one or several chromosomes,
## splitting chromosomes into chunks of ~5MB

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use POSIX;

sub usage {
	print STDERR basename($0) . " [options] [-- impute2 options]\n";
	print STDERR "Options:\n";
	print STDERR "   --gen-prefix: Prefix for genotype files.\n";
	print STDERR "   --gen-suffix: Suffix for genotype files.\n";
	print STDERR "   --phased: Flag indicating that study genotypes have been pre-phased.\n";
	print STDERR
	  "   --length: File with chromosome length information. This file should have at least two columns with the chromosome name in the first and length in the second column.\n";
	print STDERR
	  "   --chromosomes: List with chromosome names to process. This may include ranges, e.g., 1-5,7,9,Y. [default: 1-22]\n";
	print STDERR "   --map-prefix: Prefix for recombination map files.\n";
	print STDERR "   --map-suffix: Suffix for recombination map files.\n";
	print STDERR "   --output: Name of output directory.\n";
	print STDERR "   --hap-prefix: Prefix for reference haplotype files.\n";
	print STDERR "   --hap-suffix: Suffix for reference haplotype files.\n";
	print STDERR "   --legend-prefix: Prefix for legend files.\n";
	print STDERR "   --legend-suffix: Suffix for legend files.\n";
	print STDERR "   --submit: The command (and options) that should be used job submission. [\"qsub -cwd -V -pe shmem 2 -b y\"]\n";
	print STDERR "\nimpute2 options:\n";
	print STDERR
	  "   The options -m, -h, -l, -g, -int and -o will be generated by this script based on the \
	options given above. Other impute2 parameters may be added to the command line after a '--'.\n";

	exit();
}

my (
	$gPref,  $gSuf,  $lengthFile, $chromString,
	@chroms, $mPref, $mSuf,       $hPref,
	$hSuf,   $lPref, $lSuf,       %chromLength,
	@entry,  $cmd,   $cmd2,       $output,
	$submit, $phased
);

$chromString = '1-22';
$submit = 'qsub -cwd -V -pe shmem 2 -b y';
$phased = '';
my $status = GetOptions(
	"gen-prefix=s"    => \$gPref,
	"gen-suffix=s"    => \$gSuf,
	"length=s"        => \$lengthFile,
	"chromosomes=s"   => \$chromString,
	"map-prefix=s"    => \$mPref,
	"map-suffix=s"    => \$mSuf,
	"hap-prefix=s"    => \$hPref,
	"hap-suffix=s"    => \$hSuf,
	"legend-prefix=s" => \$lPref,
	"legend-suffix=s" => \$lSuf,
	"output=s"        => \$output,
	"submit=s"        => \$submit,
	"phased"          => \$phased
);

if (   !$status
	or not defined $gPref
	or not defined $gSuf
	or not defined $mPref
	or not defined $mSuf
	or not $lengthFile) {
	usage();
}

## parse chromosome string
@chroms = ();
for my $chrom (split /,/, $chromString) {
	if ($chrom =~ /(chr)?(\d+)-(chr)?(\d+)/) {
		push @chroms, ($2 .. $4);
	}
	else {
		push @chroms, $chrom;
	}
}

## read chromosome lengths
open LENGTH, $lengthFile or die "Cannot read $lengthFile: $!";
while (<LENGTH>) {
	@entry = split /\s/;
	$entry[0] =~ s/chr//;
	$chromLength{ $entry[0] } = $entry[1];
}

## generate impute commands
for my $chrom (@chroms) {
	$cmd = "impute2 ";
	if($phased){
		$cmd .= "-use_prephased_g -known_haps_g $gPref$chrom$gSuf ";
	}
	else{
		$cmd .= "-g $gPref$chrom$gSuf ";
	}
	$cmd .= "-m $mPref" . $chrom . "$mSuf";
	if (defined $hPref) {
		$cmd .= " -h $hPref";
		if (defined $hSuf) {
			$cmd .= $chrom . "$hSuf";
		}
	}
	if (defined $lPref) {
		$cmd .= " -l $lPref";
		if (defined $lSuf) {
			$cmd .= $chrom . "$lSuf";
		}
	}
	$cmd .= ' ' . join(' ', @ARGV);
	for (my $i = 0; $i < ceil($chromLength{$chrom} / 5000000); $i++) {
		$cmd2 = $cmd . " -int " . ($i * 5000000 + 1) . " ";
		if (($i + 1) * 5000000 < $chromLength{$chrom}) {
			$cmd2 .= ($i + 1) * 5000000;
		}
		else {
			$cmd2 .= $chromLength{$chrom};
		}
		$cmd2 .=
		    " -o $output/"
		  . basename($gPref)
		  . $chrom
		  . ".chunk"
		  . sprintf("%03d", $i + 1)
		  . "$gSuf"
		  . ".impute2";
		## submit to cluster
		system("$submit -N impute2_chr$chrom." . sprintf("%03d", $i + 1) . " $cmd2");
	}
}

