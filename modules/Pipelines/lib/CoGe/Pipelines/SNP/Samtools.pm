package CoGe::Pipelines::SNP::Samtools;

use v5.14;
use warnings;
use strict;

use Carp;
use Data::Dumper;
use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(fileparse basename);

use CoGe::Accessory::Jex;
use CoGe::Accessory::Utils;
use CoGe::Accessory::Web;
use CoGe::Core::Storage qw(get_genome_file get_experiment_files get_workflow_paths);
use CoGe::Pipelines::SNP::Tasks;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(build run);
our $CONFIG = CoGe::Accessory::Web::get_defaults();
our $JEX = CoGe::Accessory::Jex->new( host => $CONFIG->{JOBSERVER}, port => $CONFIG->{JOBPORT} );

sub run {
    my %opts = @_;

    # Required arguments
    my $experiment = $opts{experiment} or croak "An experiment must be specified";
    my $user = $opts{user} or croak "A user was not specified";

    my $workflow = $JEX->create_workflow( name => 'Running the SNP-finder pipeline', init => 1 );
    my ($staging_dir, $result_dir) = get_workflow_paths( $user->name, $workflow->id );
    $workflow->logfile( catfile($staging_dir, 'debug.log') );

    my @jobs = build({
        experiment => $experiment,
        staging_dir => $staging_dir,
        user => $user,
        wid  => $workflow->id,
    });

    # Add all the jobs to the workflow
    foreach (@jobs) {
        $workflow->add_job(%{$_});
    }

    # Submit the workflow
    my $result = $JEX->submit_workflow($workflow);
    if ($result->{status} =~ /error/i) {
        return (undef, "Could not submit workflow");
    }

    return ($result->{id}, undef);
}

sub build {
    my $opts = shift;

    # Required arguments
    my $experiment = $opts->{experiment};
    my $user = $opts->{user};
    my $wid = $opts->{wid};
    my $staging_dir = $opts->{staging_dir};

    my $genome = $experiment->genome;
    my $fasta_cache_dir = catdir($CONFIG->{CACHEDIR}, $genome->id, "fasta");

    my $fasta_file = get_genome_file($genome->id);
    my $files = get_experiment_files($experiment->id, $experiment->data_type);
    my $bam_file = shift @$files;
    my $basename = to_filename($bam_file);
    my $reheader_fasta =  to_filename($fasta_file) . ".filtered.fasta";

    my $conf = {
        staging_dir    => $staging_dir,

        bam            => $bam_file,
        fasta          => catfile($fasta_cache_dir, $reheader_fasta),
        bcf            => catfile($staging_dir, qq[snps.raw.bcf]),
        vcf            => catfile($staging_dir, qq[snps.flt.vcf]),

        experiment     => $experiment,
        username       => $user->name,
        source_name    => $experiment->source->name,
        wid            => $wid,
        gid            => $genome->id,
    };

    my @jobs;

    # Build all the job
    push @jobs, create_fasta_reheader_job({
        fasta => $fasta_file,
        cache_dir => $fasta_cache_dir,
        reheader_fasta => $reheader_fasta,
    });

    push @jobs, create_find_snps_job($conf);
    push @jobs, create_filter_snps_job($conf);
    push @jobs, create_load_vcf_job($conf);

    return @jobs;
}

1;
