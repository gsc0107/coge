package CoGe::Request::Genome;

use Moose;
with qw(CoGe::Request::Request);

use CoGe::Request::Request;
use JSON;

sub is_valid {
    my $self = shift;

    # Verify that the genome exists
    my $gid = $self->parameters->{gid} || $self->parameters->{genome_id};
    return unless $gid;
    my $genome = $self->db->resultset("Genome")->find($gid);
    return defined $genome ? 1 : 0;
}

sub has_access {
    my $self = shift;
    return unless defined $self->{user};

    my $gid = $self->parameters->{gid} || $self->parameters->{genome_id};
    return unless $gid;
    my $genome = $self->db->resultset("Genome")->find($gid);
    return $self->user->has_access_to_genome($genome);
}

1;
