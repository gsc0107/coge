#!/usr/bin/perl -w

use v5.14;
use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Path;
use Getopt::Long;
use IO::Compress::Gzip;
use Text::Wrap;

use CoGeX;
use CoGe::Accessory::Web;
use CoGe::Accessory::SynMap_report;

our ($synfile, $OUTPUT, $coge, $DEBUG, $join, $CONFIG, $CONFIG_FILE, $GUNZIP, $TAR);

GetOptions(
    "config|cfg=s" => \$CONFIG_FILE,
    "debug"        => \$DEBUG,

    # Input is the aligncoords file from SynMap
    # Output is the name of the file to be compressed
    "input|i=s"    => \$synfile,
    "output|o=s"   => \$OUTPUT,

    #Is the output sequence going to be joined together using "N"s for gaps.
    #Set to a number to be true, and whatever number it is will be the number of N's used to join sequence.
    "join=i"       => \$join,
);

$join = 100 unless defined $join;

croak "Configuration file is missing" unless $CONFIG_FILE and -r $CONFIG_FILE;
croak "Input file is missing" unless $synfile and -r $synfile;
croak "Output filename is missing" unless $OUTPUT;

$CONFIG  = CoGe::Accessory::Web::get_defaults($CONFIG_FILE);
$GUNZIP  = $CONFIG->{GUNZIP};
$TAR     = $CONFIG->{TAR};

if($CONFIG) {
    my $DBNAME = $CONFIG->{DBNAME};
    my $DBHOST = $CONFIG->{DBHOST};
    my $DBPORT = $CONFIG->{DBPORT};
    my $DBUSER = $CONFIG->{DBUSER};
    my $DBPASS = $CONFIG->{DBPASS};
    my $connstr =
    "dbi:mysql:dbname=" . $DBNAME . ";host=" . $DBHOST . ";port=" . $DBPORT;

    $coge = CoGeX->connect( $connstr, $DBUSER, $DBPASS );
}

my $synmap_report = new CoGe::Accessory::SynMap_report;
$synfile = gunzip($synfile);
gunzip( $synfile . ".gz" ); #EL: gunzip was returning the input filename with the .gz extension.  Causing failures later in the code.

my ( $chr1, $chr2, $dsgid1, $dsgid2 ) =
  $synmap_report->parse_syn_blocks( file => $synfile );
( $chr1, $chr2, $dsgid1, $dsgid2 ) = ( $chr2, $chr1, $dsgid2, $dsgid1 )
  if scalar @$chr1 < scalar @$chr2;

my ($dsg1) = $coge->resultset('Genome')->search( { 'me.genome_id' => $dsgid1 } );
#my ($dsg1) = $coge->resultset('Genome')->search( { 'me.genome_id' => $dsgid1 },
#    { join => 'genomic_sequences', prefetch => 'genomic_sequences' } );

my ($dsg2) = $coge->resultset('Genome')->search( { 'me.genome_id' => $dsgid2 } );
#my ($dsg2) = $coge->resultset('Genome')->search( { 'me.genome_id' => $dsgid2 },
#    { join => 'genomic_sequences', prefetch => 'genomic_sequences' } );

unless ($dsg1) {
    print STDERR "Unable to get genome object for genome_id=$dsgid1.\n";
    exit;
}

unless ($dsg2) {
    print STDERR "Unable to get genome object for genome_id=$dsgid2.\n";
    exit;
}

my $logfile = "log.txt";
open( LOG, ">" . $logfile );
my $org1 =
    "Reference genome: "
  . $dsg1->organism->name . "v"
  . $dsg1->version . " "
  . $dsg1->source->[0]->name . " ";
$org1 .= $dsg1->name if $dsg1->name;
$org1 .= " (dsgid" . $dsg1->id . "): " . $dsg1->genomic_sequence_type->name;
my $org2 .=
    "Pseudoassembly genome: "
  . $dsg2->organism->name . "v"
  . $dsg2->version . " "
  . $dsg2->source->[0]->name . " ";
$org2 .= $dsg2->name if $dsg2->name;
$org2 .= " (dsgid" . $dsg2->id . "): " . $dsg2->genomic_sequence_type->name;
print LOG $org1, "\n";
print LOG $org2, "\n";
print LOG "Syntenic file: $synfile\n";

my $fafile = "pseudoassembly.faa";
open( FAA, ">$fafile" );
my $AGPfile = "agp.txt";
open( AGP, ">$AGPfile" );
print AGP qq{# Generated by the comparative genomics platform CoGe
# http://genomevolution.org
# Created by SynMap
};

print AGP "# " . $org1, "\n";
print AGP "# " . $org2, "\n";

process_sequence($chr1);
close FAA;
close AGP;

my @files = ($logfile, $fafile, $AGPfile);
my $cmd = qq($TAR -czvf $OUTPUT ) . join(" ", @files);
print LOG "Compressing directory: $cmd\n";
close LOG;
`$cmd`;

sub process_sequence {
    my $chrs = shift;
    my %dsg
      ; #store CoGe dataset group objects so we don't have to create them multiple times
    my $count = 0;    #number of blocks processed per matched chromosome
    my %out_chrs
      ; #seen chromosomes for printing, let's me know when to start a new fasta sequence
    my %in_chrs
      ; #seen chromosomes coming in, need to use this to identify those pieces that weren't used and to be lumped under "unknown"
    my $seq;       #sequence to process and dump
    my $header;    #header for sequence;
    my $agp_file
      ; #store the assembly information in an AGP file: http://www.ncbi.nlm.nih.gov/projects/genome/assembly/agp/AGP_Specification.shtml
    my $pos      = 1;
    my $part_num = 1;

    foreach my $item (@$chrs) {
        my $chr     = $item->{chr};
        my $out_chr = $item->{matching_chr}->[0];
        my $dsgid   = $item->{dsgid};
        unless ($dsgid) {
            print
              "Error!  Problem generating sequence.  No genome id specified!";
            return;
        }
        my $dsg = $dsg{$dsgid};
        $dsg = $coge->resultset('Genome')->find($dsgid) unless $dsg;
        $dsg{ $dsg->id } = $dsg;
        my $strand = $item->{rev} ? -1 : 1;
        if ( $seq && !$out_chrs{$out_chr} ) {
            #we have a new chromosome.  Dump the old and get ready for the new;
            print_sequence( header => $header, seq => $seq );
            $count    = 0;
            $seq      = undef;
            $part_num = 1;
            $pos      = 1;
        }
        if ($join) {
            if ($count) {
                $seq .= "N" x $join;
                print AGP join( "\t",
                    $out_chr, $pos, $pos + $join - 1,
                    $part_num, "N", $join, "contig", "no", "" ),
                  "\n";
                $pos += $join;
                $part_num++;
            }
            else    #need to print fasta header
            {
                $header = "$out_chr";
            }
            my $tmp_seq =
              $dsg->get_genomic_sequence( chr => $chr, strand => $strand );
            $seq .= $tmp_seq;
            my $seq_len = length($tmp_seq);
            my $ori = $strand eq "1" ? "+" : "-";
            print AGP join( "\t",
                $out_chr, $pos, $pos + $seq_len - 1,
                $part_num, "W", $chr, 1, $seq_len, $ori ),
              "\n";
            $part_num++;
            $pos += $seq_len;
            $count++;
            $out_chrs{$out_chr}++;
            $in_chrs{ uc($chr) }++;
        }
        else {
            print FAA $dsg->fasta( chr => $chr );
        }
    }
    if ($seq) {
        print_sequence( header => $header, seq => $seq );
    }
    #need to get all the pieces that didn't fit
    $header   = "Unknown";
    $seq      = undef;
    $count    = 0;
    $part_num = 1;
    $pos      = 1;
    foreach my $dsg ( values %dsg ) {
        foreach my $chr ( $dsg->chromosomes ) {
            next if $in_chrs{ uc($chr) };
            if ($count) {
                $seq .= "N" x $join;
                print AGP join( "\t",
                    $header, $pos, $pos + $join - 1,
                    $part_num, "N", $join, "contig", "no", "" ),
                  "\n";
                $pos += $join;
                $part_num++;
            }
            my $tmp_seq = $dsg->get_genomic_sequence( chr => $chr );
            $seq .= $tmp_seq;
            my $seq_len = length($tmp_seq);
            print AGP join( "\t",
                $header, $pos, $pos + $seq_len - 1,
                $part_num, "W", $chr, 1, $seq_len, "+" ),
              "\n";
            $part_num++;
            $pos += $seq_len;
            $count++;
        }
    }
    print_sequence( header => $header, seq => $seq );
}

sub print_sequence {
    my %opts   = @_;
    my $header = $opts{header};
    my $seq    = $opts{seq};
    #      $Text::Wrap::columns=80;
    print FAA ">" . $header, "\n";
    #      print FAA wrap('','',$seq),"\n";
    print FAA $seq, "\n";
}

sub gunzip {
    my $file = shift;
    return $file unless $file;
    return $file unless $file =~ /\.gz$/;
    my $tmp = $file;
    $tmp =~ s/\.gz$//;
    return $tmp if -r $tmp;
    `$GUNZIP $file` if -r $file;
    return -r $tmp ? $tmp : $file;
}
