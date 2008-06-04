package CoGeX::Feature;

use strict;
use warnings;
use base 'DBIx::Class';
use CoGe::Accessory::genetic_code;
use Text::Wrap;
use Data::Dumper;
use CoGe::Accessory::Annotation;

__PACKAGE__->load_components("PK::Auto", "ResultSetManager", "Core");
__PACKAGE__->table("feature");
__PACKAGE__->add_columns(
  "feature_id",{ data_type => "INT", default_value => undef, is_nullable => 0, size => 10 },
  "feature_type_id",{ data_type => "INT", default_value => 0, is_nullable => 0, size => 10 },
  "dataset_id",{ data_type => "INT", default_value => 0, is_nullable => 0, size => 10 },
  "start",{ data_type => "INT", default_value => 0, is_nullable => 1, size => 10 },
  "stop",{ data_type => "INT", default_value => 0, is_nullable => 1, size => 10 },
  "chromosome",{ data_type => "VARCHAR", default_value => 0, is_nullable => 1, size => 50 },
  "strand",{ data_type => "VARCHAR", default_value => 0, is_nullable => 1, size => 2 },
);

__PACKAGE__->set_primary_key("feature_id");

# feature has many feature_names
__PACKAGE__->has_many( 'feature_names' => "CoGeX::FeatureName", 'feature_id');

# feature has many annotations
__PACKAGE__->has_many( 'annotations' => "CoGeX::Annotation", 'feature_id');

# feature has many locations
__PACKAGE__->has_many( 'locations' => "CoGeX::Location", 'feature_id');

# feature has many sequences - note this is non-genomic sequence (see
# genomic_sequence() and sequence
__PACKAGE__->has_many( 'sequences' => "CoGeX::Sequence", 'feature_id');

# feature_type has many features
__PACKAGE__->belongs_to("feature_type" => "CoGeX::FeatureType", 'feature_type_id');

# dataset has many features
__PACKAGE__->belongs_to("dataset" => "CoGeX::Dataset", 'dataset_id');


#__PACKAGE__->mk_group_accessors(['start', 'stop', 'chromosome', 'strand']);



sub esearch : ResultSet {
    my $self = shift;
    my $join = $_[1]{'join'};
    map { push(@$join, $_ ) } 
        ();


    my $prefetch = $_[1]{'prefetch'};
    map { push(@$prefetch, $_ ) } 
        ('feature_type','locations', 
            { 'dataset' => 'organism' }
        );

    $_[1]{'join'} = $join;
    $_[1]{'prefetch'} = $prefetch;
    my $rs = $self->search(@_);
    return $rs;

}
sub type
  {
    my $self = shift;
    return $self->feature_type();
  }

sub organism
  {
    my $self = shift;
    return $self->dataset->organism();
  }

sub org
  {
    my $self = shift;
    return $self->organism();
  }

sub names
  {
    my $self = shift;
    if ($self->{_names})
      {
	return wantarray ? @{$self->{_names}} : $self->{_names};
      }
#    my @names =  sort $self->feature_names()->get_column('name')->all;
    my @names;
    foreach my $name (sort {$a->name cmp $b->name} $self->feature_names())
      {
	if ($name->primary_name)
	  {
	    unshift @names, $name->name;
	  }
	else
	  {
	    push @names, $name->name;
	  }
      }
    $self->{_names}=\@names;
    return wantarray ? @names : \@names;
  }

sub primary_name
 {
   my $self = shift;
   my ($nameo) = $self->feature_names({primary_name=>1});
   my ($name) = ref($nameo) =~ /name/i ? $nameo->name : $self->names;
 }

sub locs
  {
    my $self = shift;
    return $self->locations();
  }

sub seqs
  {
    my $self = shift;
    return $self->sequences();
  }

sub eannotations
  {
    my $self = shift;
    return $self->annotations(undef,{prefetch=>['annotation_type']});
  }

sub annos
  {
    shift->eannotations(@_);
  }

sub length
    {
      my $self = shift;
      my $length = 0;
      map {$length+=($_->stop-$_->start+1)} $self->locations;
      return $length;
    }

################################################ subroutine header begin ##

=head2 annotation_pretty_print

 Usage     : my $pretty_annotation = $feat->annotation_pretty_print
 Purpose   : returns a string with information and annotations about a feature
             in a nice format with tabs and new-lines and the like.
 Returns   : returns a string
 Argument  : none
 Throws    : 
 Comments  : uses Coge::Genome::Accessory::Annotation to build the annotations,
           : specifying delimters, and printing to string.   Pretty cool object.

See Also   : CoGe::Genome::Accessory::Annotation

=cut

################################################## subroutine header end ##


sub annotation_pretty_print
  {
    my $self = shift;
    my $anno_obj = new CoGe::Accessory::Annotation(Type=>"anno");
    $anno_obj->Val_delimit("\n");
    $anno_obj->Val_delimit("\n");
    $anno_obj->Add_type(0);
    $anno_obj->String_end("\n");
    my $start = $self->start;
    my $stop = $self->stop;
    my $chr = $self->chr;
    my $strand = $self->strand;
    #look into changing this to set_id
    my $info_id = $self->dataset->id;
    my $location = "Chr ".$chr." ";
    $location .= join (", ", map {$_->start."-".$_->stop} sort {$a->start <=> $b->start} $self->locs);
    $location .="(".$strand.")";
    #my $location = "Chr ".$chr. "".$start."-".$stop.""."(".$strand.")";
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"Location", Values=>[$location], Type_delimit=>": ", Val_delimit=>" "));
    my $anno_type = new CoGe::Accessory::Annotation(Type=>"Name(s)");
    $anno_type->Type_delimit(": ");
    $anno_type->Val_delimit(", ");
    foreach my $name ($self->names)
      {
	$anno_type->add_Annot($name);
      }
    
    $anno_obj->add_Annot($anno_type);
    foreach my $anno (sort {$b->type->name cmp $a->type->name} $self->annos)
      {
	my $type = $anno->type();
	my $group = $type->group();
	my $anno_type = new CoGe::Accessory::Annotation(Type=>$type->name);
	$anno_type->Val_delimit("\n");

	$anno_type->add_Annot($anno->annotation);
	if (ref ($group) =~ /group/i)
	  {
	    my $anno_g = new CoGe::Accessory::Annotation(Type=>$group->name);
	    $anno_g->add_Annot($anno_type);
	    $anno_g->Type_delimit(": ");
	    $anno_g->Val_delimit(", ");
	    $anno_obj->add_Annot($anno_g);
	  }
	else
	  {
	    $anno_type->Type_delimit(": ");
	    $anno_obj->add_Annot($anno_type);
	  }
      }
    my $ds = $self->dataset;
    my $org = $ds->organism->name;
    $org .= ": ".$ds->organism->description if $ds->organism->description;
    
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"Organism", Values=>[$org], Type_delimit=>": ", Val_delimit=>" "));
    
    return $anno_obj->to_String;
  }


################################################ subroutine header begin ##

=head2 annotation_pretty_print_html

 Usage     : my $pretty_annotation_html = $feat->annotation_pretty_print_html
 Purpose   : returns a string with information and annotations about a feature
             in a nice html format with breaks and class tags (called "annotation")
 Returns   : returns a string
 Argument  : none
 Throws    : 
 Comments  : uses Coge::Genome::Accessory::Annotation to build the annotations,
           : specifying delimters, and printing to string.   Pretty cool object.

See Also   : CoGe::Accessory::Annotation

=cut

################################################## subroutine header end ##


sub annotation_pretty_print_html
  {
    my $self = shift;
    my %opts = @_;
    my $loc_link = $opts{loc_link};
    $loc_link = "SeqView.pl" unless defined $loc_link;
    my $anno_obj = new CoGe::Accessory::Annotation(Type=>"anno");
    $anno_obj->Val_delimit("<BR/>");
    $anno_obj->Add_type(0);
    $anno_obj->String_end("<BR/>");
    my $start = $self->start;
    my $stop = $self->stop;
    my $chr = $self->chr;
    my $strand = $self->strand;
    my $dataset_id = $self->dataset->id;
    my $anno_type = new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">"."Name(s):"."</span>");
    $anno_type->Type_delimit("");
    $anno_type->Val_delimit(", ");
    my $outname;
    foreach my $name ($self->names)
      {
	$outname = $name unless $outname;
	$anno_type->add_Annot("<a class=\"data link\" href=\"FeatView.pl?accn=".$name."\" target=_new>".$name."</a>");
      }
    
    $anno_obj->add_Annot($anno_type);
    foreach my $anno (sort {$b->type->name cmp $a->type->name} $self->annos)
      {
	my $type = $anno->type();
	my $group = $type->group();
	my $anno_name = $type->name;
	$anno_name = "<span class=\"title4\">". $anno_name."</span>" unless ref($group) =~ /group/i;
	
	my $anno_type = new CoGe::Accessory::Annotation(Type=>$anno_name);
	$anno_type->Val_delimit(", ");

	$anno_type->add_Annot("<span class=\"data\">".$anno->annotation."</span>");
	if (ref ($group) =~ /group/i)
	  {
	    my $anno_g = new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">".$group->name."</span>");
	    $anno_g->add_Annot($anno_type);
	    $anno_g->Type_delimit(": ");
	    $anno_g->Val_delimit(", ");
#	    $anno_g->Val_delimit(" ");
	    $anno_obj->add_Annot($anno_g);
	  }
	else
	  {
	    $anno_type->Type_delimit(": ");
	    $anno_obj->add_Annot($anno_type);
	  }
      }
    my $location = "Chr ".$chr." ";
    $location .= join (", ", map {$_->start."-".$_->stop} sort {$a->start <=> $b->start} $self->locs);
    $location .="(".$strand.")";
    my $featid = $self->id;
    $location = qq{<a href="$loc_link?featid=$featid&start=$start&stop=$stop&chr=$chr&dsid=$dataset_id&strand=$strand&featname=$outname" target=_new>}.$location."</a>" if $loc_link;
    $location = qq{<span class="data">$location</span>};
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\"><a href=\"GeLo.pl?chr=$chr&ds=$dataset_id&x=$start&z=5\" target=_new>Location</a></span>", Values=>[$location], Type_delimit=>": ", Val_delimit=>" "));
    my $ds=$self->dataset;
    my $dataset = qq{<a href = "GenomeView.pl?dsid=}.$ds->id."\" target=_new>".$ds->name;
    $dataset .= ": ".$ds->description if $ds->description;
    $dataset .= "</a>";
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">Dataset</span>", Values=>[$dataset], Type_delimit=>": ", Val_delimit=>" "));
    my $org = qq{<a href = "GenomeView.pl?oid=}.$ds->organism->id."\" target=_new>".$ds->organism->name;
    $org .= ": ".$ds->organism->description if $ds->organism->description;
    $org .= "</a>";
    
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">Organism</span>", Values=>[$org], Type_delimit=>": ", Val_delimit=>" "));
    my ($gc, $at) = $self->gc_content;
    $gc*=100;
    $at*=100;
    $anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">DNA content</span>", Values=>["GC: $gc%","AT: $at%"], Type_delimit=>": ", Val_delimit=>" "));
    my ($wgc, $wat) = $self->wobble_content;
    if ($wgc || $wat)
      {
	$wgc*=100;
	$wat*=100;
	$anno_obj->add_Annot(new CoGe::Accessory::Annotation(Type=>"<span class=\"title4\">Wobble content</span>", Values=>["GC: $wgc%","AT: $wat%"], Type_delimit=>": ", Val_delimit=>" "));
      }
    return $anno_obj->to_String;
  }




################################################ subroutine header begin ##

=head2 genbank_location_string

 Usage     : my $genbank_loc = $feat->genbank_location_string
 Purpose   : generates a genbank location string for the feature in genomic coordinates or
           : based on a recalibration number that is user specified
           : e.g.: complement(join(10..100,200..400))
 Returns   : a string
 Argument  : hash:  recalibrate => number of positions to subtract from genomic location
 Throws    : none
 Comments  : 
           : 

See Also   : 

=cut

################################################## subroutine header end ##


sub genbank_location_string
  {
    my $self = shift;
    my %opts = @_;
    my $recal = $opts{recalibrate};
    my $string;
    my $count= 0;
    my $comp = 0;
    foreach my $loc (sort {$a->start <=> $b->start}  $self->locs())
      {
  #?
	# $comp = 1 if $loc->strand =~ "-";
	$comp = 1 if $loc->strand == "-1";
	$string .= "," if $count;
	$string .= $recal ? ($loc->start-$recal+1)."..".($loc->stop-$recal+1): $loc->start."..".$loc->stop;
	$count++;
      }
    $string = "join(".$string.")" if $count > 1;
    $string = "complement(".$string.")" if $comp;
    return $string;
  }


################################################ subroutine header begin ##

=head2 start

 Usage     : my $feat_start = $feat->start
 Purpose   : returns the start of the feature (does not take into account the strand on which
             the feature is located)
 Returns   : a string, number usually
 Argument  : none
 Throws    : 
 Comments  : this simply calles $feat->locs, sorts them based on their starting position, and
           : returns the smallest position

See Also   : 

=cut

################################################## subroutine header end ##


#sub start
#  {
#    my $self = shift;
#    return $self->{_start} if $self->{_start};
#    my @loc =  $self->locations({},
#				 {
#				  order_by=>'start asc',
#				 });
#    $self->{_start}=($loc[0]->start);
#    $self->{_stop}=($loc[-1]->stop);
#    $self->{_strand}=($loc[0]->strand);
#    $self->{_chromosome}=($loc[0]->chromosome);
#    return $self->{_start};
#  }

################################################ subroutine header begin ##

=head2 stop

 Usage     : my $feat_end = $feat->stop
 Purpose   : returns the end of the feature (does not take into account the strand on which
             the feature is located)
 Returns   : a string, number usually
 Argument  : none
 Throws    : 
 Comments  : this simply calles $feat->locs, sorts them based on their ending position, and
           : returns the largest position

See Also   : 

=cut

################################################## subroutine header end ##


#sub stop
#  {
#    my $self = shift;
#    return $self->{_stop} if $self->{_stop};
#    my @loc =  $self->locations({},
#				 {
#				  order_by=>'stop desc',
#				 });
#    $self->{_start}=($loc[-1]->start);
#    $self->{_stop}=($loc[0]->stop);
#    $self->{_strand}=($loc[0]->strand);
#    $self->{_chromosome}=($loc[0]->chromosome);
#    return $self->{_stop};
#  }
################################################ subroutine header begin ##

=head2 chromosome

 Usage     : my $chr = $feat->chromosome
 Purpose   : return the chromosome of the feature
 Returns   : a string
 Argument  : none
 Throws    : none
 Comments  : returns $self->locs->next->chr
           : 

See Also   : 

=cut

################################################## subroutine header end ##


#sub chromosome
#  {
#    my $self = shift;
#    return $self->{_chromosome} if $self->{_chromosome};
#    $self->start;
#    return $self->{_chromosome};
#  }
#
################################################# subroutine header begin ##

=head2 chr

 Usage     : my $chr = $feat->chr
 Purpose   : alias for $feat->chromosome

=cut

################################################## subroutine header end ##

sub chr
  {
    my $self = shift;
    return $self->chromosome;
  }

################################################ subroutine header begin ##

=head2 strand

 Usage     : my $strand = $feat->strand
 Purpose   : return the chromosome strand of the feature
 Returns   : a string (usally something like 1, -1, +, -, etc)
 Argument  : none
 Throws    : none
 Comments  : returns $self->locs->next->strand
           : 

See Also   : 

=cut

################################################## subroutine header end ##


#sub strand
#  {
#    my $self = shift;    
#    return $self->{_strand} if $self->{_strand};
#    $self->start;
#    return $self->{_strand};
#  }


################################################ subroutine header begin ##

=head2 version

 Usage     : my $version = $feat->version
 Purpose   : return the dataset version of the feature
 Returns   : an integer
 Argument  : none
 Throws    : none
 Comments  : returns $self->dataset->version
           : 

See Also   : 

=cut

################################################## subroutine header end ##


sub version
  {
    my $self = shift;
    return $self->dataset->version();
  }

################################################ subroutine header begin ##

=head2 genomic_sequence

 Usage     : my $genomic_seq = $feat->genomic_sequence
 Purpose   : gets the genomic seqence for a feature
 Returns   : a string
 Argument  : none
 Comments  : This method simply creates a CoGe object and calls:
             get_genomic_sequence_for_feature($self)
See Also   : CoGe

=cut

################################################## subroutine header end ##

sub genomic_sequence {
  my $self = shift;
  my %opts = @_;
  my $up = $opts{up} || $opts{upstream} || $opts{left};
  my $down = $opts{down} || $opts{downstream} || $opts{right};
  my $dataset = $self->dataset();
  my @sequences;
  my @locs = map {[$_->start,$_->stop,$_->chromosome,$_->strand]}sort { $a->start <=> $b->start } $self->locations() ;
  ($up,$down) = ($down, $up) if ($self->strand =~/-/); #must switch these if we are on the - strand;
  if ($up)
    {
      my $start = $locs[0][0]-$up;
      $start = 1 if $start < 1;
      $locs[0][0]=$start;
    }
  if ($down)
    {
      my $stop = $locs[-1][1]+$down;
      $locs[-1][1]=$stop;
    }
  my $chr = $self->chromosome || $locs[0][2];
  my $start = $locs[0][0];
  my $stop = $locs[-1][1];
  my $full_seq = $dataset->get_genomic_sequence(
						chromosome=>$chr,
						skip_length_check=>1,
						start=>$start,
						stop=>$stop,
					       );
  foreach my $loc (@locs){
    if ($loc->[0]-$start+$loc->[1]-$loc->[0]+1 > CORE::length ($full_seq))
      {
	print STDERR "Error in feature->genomic_sequence, location is outside of retrieved sequence: \n";
	use Data::Dumper;
	print STDERR Dumper \@locs;
	print STDERR CORE::length ($full_seq),"\n";
	print STDERR Dumper {
	  chromosome=>$chr,
	    skip_length_check=>1,
	      start=>$start,
		stop=>$stop,
		  dataset=>$dataset->id,
		    feature=>$self->id,
	      };
#	die;
#	next;
      }

      my $this_seq = substr($full_seq
                          , $loc->[0] - $start
                          , $loc->[1] - $loc->[0] + 1);
      if ($loc->[3] == -1){
            unshift @sequences, $self->reverse_complement($this_seq);
      }else{
            push @sequences, $this_seq;
      }
  }        
  return wantarray ? @sequences : join( "", @sequences );
}

sub genomic_sequence_old {
  my $self = shift;
  my $dataset = $self->dataset();
  my @sequences;
  foreach my $loc (sort {$a->start <=> $b->start} $self->locations())
    {
      #  while ( my $loc = $lociter->next() ) {
      my $fseq = $dataset->get_genome_sequence(
					       chromosome=>$loc->chromosome(),
					       skip_length_check=>1,
					       start=>$loc->start,
					       stop=>$loc->stop );
      if ( $loc->strand == -1 ) {
	push @sequences, $self->reverse_complement($fseq);
      } else {
	push @sequences, $fseq;
      }
    }
  return wantarray ? @sequences : join( "", @sequences );
}

sub genome_sequence
  {
   shift->genomic_sequence(@_);
  }

sub has_genomic_sequence
  {
    my $self = shift;
    return 1 if $self->dataset->has_genomic_sequence;
    return 0;
  }

################################################ subroutine header begin ##

=head2 blast_bit_score

 Usage     : my $bit_score = $feature->blast_bit_score();
 Purpose   : returns the blast bit score for the feature's self-self identical hit
 Returns   : an int -- the blast bit score
 Argument  : optional hash
             match    => the score for a nucleotide match. DEFAULT: 1
             mismatch => the score for a nucleotide mismatch.  DEFAULT: -3
 Throws    : 
 Comments  : 
           : 

See Also   : 

=cut

################################################## subroutine header end ##

sub blast_bit_score
  {
    my $self = shift;
    my %opts = @_;
    my $match = $opts{match} || 1;
    my $mismatch = $opts{mismatch} || -3;
    my $lambda = $self->_estimate_lambda(match=>$match, mismatch=>$mismatch);
    my $seq = $self->genomic_sequence();
    warn "No genomic sequence could be obtained for this feature object.  Can't calculate a blast bit score.\n" unless $seq;
    my $bs = sprintf("%.0f", $lambda*CORE::length($seq)*$match/log(2));
    return $bs;
  }

################################################ subroutine header begin ##

=head2 _estimate_lambda

 Usage     : my $lambda = $feature->_estimate_lambda
 Purpose   : estimates lambda for calculating blast bit scores.  Lambda is
             a matrix-specific constant for normalizing raw blast scores 
 Returns   : a number, lambda
 Argument  : optional hash
             match    => the score for a nucleotide match. DEFAULT: 1
             mismatch => the score for a nucleotide mismatch.  DEFAULT: -3
             precision=> the different between the high and low estimate 
                         of lambda before lambda is returned.  
                         DEFAULT: 0.001
 Throws    : a warning if there is a problem with the calcualted expected_score
             or the match score is less than 0;
 Comments  : Assumes an equal probability for each nucleotide.
           : this routine is based on example 4-1 from 
           : BLAST: An essential guide to the Basic Local Alignment Search Tool 
           : by Korf, Yandell, and Bedell published by O'Reilly press.

See Also   : 

=cut

################################################## subroutine header end ##


sub _estimate_lambda
  {
    #this routine is based on example 4-1 from BLAST: An essential guide to the Basic Local Alignment Search Tool by Korf, Yandell, and Bedell published by O'Reilly press.
    my $self = shift;
    my %opts = @_;
    my $match = $opts{match} || 1;
    my $mismatch = $opts{mismatch} || -3;
    my $precision = $opts{precision} || 0.001;
      
    use constant Pn => 0.25; #prob of any nucleotide
    my $expected_score = $match * 0.25 + $mismatch * 0.75; 
    if ($match <= 0 or $expected_score >= 0)
      {
	warn qq{
Problem with scores.  Match: $match (should be greater than 0).
             Expected score: $expected_score (should be less than 0).
};
	return 0;
      }
    # calculate lambda 
    my ($lambda, $high, $low) = (1, 2, 0); # initial estimates 
    while ($high - $low > $precision) 
      {         # precision 
	# calculate the sum of all normalized scores 
	my $sum = Pn * Pn * exp($lambda * $match) * 4 
	  + Pn * Pn * exp($lambda * $mismatch) * 12; 
	# refine guess at lambda 
	if ($sum > 1) 
	  { 
	    $high = $lambda;
	    $lambda = ($lambda + $low)/2; 
	  } 
	else 
	  {
	  $low = $lambda; 
	  $lambda = ($lambda + $high)/2; 
	}
      }
    # compute target frequency and H 
    my $targetID = Pn * Pn * exp($lambda * $match) * 4; 
    my $H = $lambda * $match    *     $targetID 
      + $lambda * $mismatch * (1 -$targetID); 
    # output 
#    print "expscore: $expected_score\n"; 
#    print "lambda:   $lambda nats (", $lambda/log(2), " bits)\n"; 
#    print "H:        $H nats (", $H/log(2), " bits)\n"; 
#    print "%ID:      ", $targetID * 100, "\n"; 

    return $lambda;
  }

sub reverse_complement
  {
    my $self = shift;
    my $seq = shift;# || $self->genomic_sequence;
    if (ref($self) =~ /Feature/)
      {
	$seq = $self->genomic_sequence unless $seq; #self seq unless we have a seq
      }
    else #we were passed a sequence without invoking self
      {
	$seq = $self unless $seq;
      }
    my $rcseq = reverse($seq);
    $rcseq =~ tr/ATCGatcg/TAGCtagc/; 
    return $rcseq;
  }

sub reverse_comp {
  shift->reverse_complement(@_);
}


sub protein_sequence {
  my $self = shift;
  my $siter = $self->sequences();
  my @sequence_objects;
  while ( my $seq = $siter->next() ) {
    push @sequence_objects, $seq;
  }

  if (@sequence_objects == 1) 
    {
      return $sequence_objects[0]->sequence_data();
    } 
  elsif ( @sequence_objects > 1 )  
    {
      return \@sequence_objects;
    } 
  else 
    {
      my ($seqs,$type) = $self->frame6_trans;
      #check to see if we can find the best translation
      my $found=0;
      while (my ($k, $v) = each %$seqs)
	{
	  if (($v =~ /\*$/)|| $v !~ /\*/)
	    {
	      next if $v =~ /\*\w/;
	      $found = $k;
	    }
	}
      if ($found)
	{
	  return $seqs->{$found};
	}
      else
	{
	  return undef;
	}
    }
}


sub frame6_trans
  {
    my $self = shift;
    my %opts = @_;
    my $trans_type = $opts{trans_type};
    my $code;
    ($code, $trans_type) = $opts{code} || $self->genetic_code(trans_type=>$trans_type);
    my $seq = $opts{seq} || $self->genomic_sequence;

    my %seqs;
    $seqs{"1"} = $self->_process_seq(seq=>$seq, start=>0, code1=>$code, codonl=>3);
    $seqs{"2"} = $self->_process_seq(seq=>$seq, start=>1, code1=>$code, codonl=>3);
    $seqs{"3"} = $self->_process_seq(seq=>$seq, start=>2, code1=>$code, codonl=>3);
    my $rcseq = $self->reverse_complement($seq);
    $seqs{"-1"} = $self->_process_seq(seq=>$rcseq, start=>0, code1=>$code, codonl=>3);
    $seqs{"-2"} = $self->_process_seq(seq=>$rcseq, start=>1, code1=>$code, codonl=>3);
    $seqs{"-3"} = $self->_process_seq(seq=>$rcseq, start=>2, code1=>$code, codonl=>3);
    return \%seqs, $trans_type;

  }

sub genetic_code
  {
    my $self = shift;
    my %opts = @_;
    my $trans_type = $opts{trans_type};
    unless ($trans_type)
      {
	foreach my $anno ($self->annotations)
	  {
	    next unless $anno->annotation_type->name eq "transl_table";
	    $trans_type = $anno->annotation;
	  }
      }
    $trans_type = 1 unless $trans_type;
    my $code = code($trans_type);
    return ($code->{code}, $code->{name});
  }
sub _process_seq
  {
    my $self = shift;
    my %opts = @_;
    my $seq = $opts{seq};
    my $start = $opts{start};
    my $code1 = $opts{code1};
    my $code2 = $opts{code2};
    my $alter = $opts{alter};
    my $codonl = $opts{codonl} || 2;
    my $seq_out;
    for (my $i = $start; $i < CORE::length ($seq); $i = $i+$codonl)
      {
	my $codon = uc(substr($seq, $i, $codonl));
	my $chr = $code1->{$codon} || $code2->{$codon};
	unless ($chr)
	  {
	    $chr= $alter if $alter;
	  }
	$seq_out .= $chr if $chr;
      }
    return $seq_out;
  }



sub percent_translation_system
  {
    my $self = shift;
    my %opts = @_;
    my $counts = $opts{counts};
    my %code1 = (
		 "W"=>1,
		 "M"=>1,
		 "L"=>1,
		 "Y"=>1,
		 "C"=>1,
		 "I"=>1,
#		 "K"=>1, #majority in code2
		 "R"=>1,
		 "Q"=>1,
		 "V"=>1,
		 "E"=>1,
		 
		);
    my $code1 = $opts{code1} || \%code1;
    my %code2 = (
		 "F"=>1,
		 "S"=>1,
		 "T"=>1,
		 "N"=>1,
		 "P"=>1,
		 "H"=>1,
		 "A"=>1,
		 "D"=>1,
		 "G"=>1,
		 "K"=>1,
		);
    my $code2 = $opts{code2} || \%code2;
    my ($seq) = $opts{seq} || $self->protein_sequence;
    return (0,0) unless $seq;
    my ($c1, $c2, $total) = (0,0,0);
    foreach (split //, $seq)
      {
	$_ = uc($_);
	$c1++ if $code1->{$_};
	$c2++ if $code2->{$_};
	$total++;
      }
    if ($counts)
      {
	return $c1, $c2, $total;
      }
    else
      {
	return (map {sprintf("%.4f", $_)} $c1/$total, $c2/$total);
      }
  }

sub aa_frequency
  {
    my $self = shift;
    my %opts = @_;
    my $counts = $opts{counts};
    my ($code) = $self->genetic_code;
    my %data = map {$_=>0} values %$code;
    my ($seq) = $opts{seq} || $self->protein_sequence;
    return \%data unless $seq;
    foreach (split //,$seq)
      {
	next if $_ eq "*";
	$data{$_}++ if defined $data{$_};
      }
    if ($counts)
      {
	return \%data;
      }
    else
      {
	my $total = 0;
	foreach (values %data)
	  {
	    $total+=$_;
	  }
	foreach my $aa (keys %data)
	  {
	    $data{$aa} = sprintf("%.4f", ($data{$aa}/$total));
	  }
	return \%data;
      }
  }

sub codon_frequency
  {
    my $self = shift;
    my %opts = @_;
    my $counts = $opts{counts};
    my $code = $opts{code};
    my $code_type = $opts{code_type};
    ($code, $code_type) = $self->genetic_code unless $code;;
    my %codon = map {$_=>0} keys %$code;
    my $seq = $self->genomic_sequence;
    my $x=0;
    while ($x<CORE::length($seq))
      {
	$codon{uc(substr($seq, $x, 3))}++;
	$x+=3;
      }
    if ($counts)
      {
	return \%codon, $code_type;
      }
    else
      {
	my $total = 0;
	foreach (values %codon)
	  {
	    $total+=$_;
	  }
	foreach my $codon (keys %codon)
	  {
	    $codon{$codon} = sprintf("%.4f", ($codon{$codon}/$total));
	  }
	return (\%codon, $code_type);
      }
  }

sub gc_content
  {
    my $self = shift;
    my %opts = @_;
    my $counts = $opts{counts};
    my $seq = $self->genomic_sequence;
    my ($gc,$at);
    $gc = $seq =~ tr/gcGC/gcGC/;
    $at = $seq =~ tr/atAT/atAT/;
    unless ($counts)
      {
	my $total = CORE::length($seq);
	return (0,0) unless $total;
	$gc = sprintf("%.4f", ($gc/$total));
	$at = sprintf("%.4f", ($at/$total));
      }
    return $gc,$at;
  }

sub wobble_content
  {
    my $self = shift;
    return unless $self->type->name =~ /cds/i;
    my $seq = $self->genomic_sequence;
    my $codon_count=0;;
    my $at_count=0;
    my $gc_count=0;
    for (my $i =0; $i < length($seq); $i+=3)
      {
        my $codon = substr ($seq, $i, 3);
        $codon_count++;
        my ($wobble) = $codon =~ /(.$)/;
        $at_count++ if $wobble =~ /[at]/i;
        $gc_count++ if $wobble =~ /[gc]/i;
      }
    my $pat = sprintf("%.4f", $at_count/$codon_count);
    my $pgc = sprintf("%.4f", $gc_count/$codon_count);
    return ($pgc, $pat);
  }

sub fasta
  {
    my $self = shift;
    my %opts = @_;
    my $col;
    $col = $opts{col};
    my $prot = $opts{protein} || $opts{prot};
    #$col can be set to zero so we want to test for defined variable
    $col = $opts{column} unless defined $col;
    $col = $opts{wrap} unless defined $col;
    $col = 100 unless defined $col;
    my $rc = $opts{rc};
    my $upstream = $opts{upstream};
    my $downstream = $opts{downstream};
    my $name_only = $opts{name_only};
    my $sep = $opts{sep}; #returns the header and sequence as separate items.
    my ($pri_name) = $self->primary_name;
    my $head = $name_only ? ">".$pri_name : ">".$self->dataset->organism->name."(v".$self->version.")".", Name: ".(join (", ", $self->names)).", Type: ".$self->type->name.", Feature Location: (Chr: ".$self->chromosome.", ".$self->genbank_location_string.")";
    $head .= " +up: $upstream" if $upstream;
    $head .= " +down: $downstream" if $downstream;
    $head .= " (reverse complement)" if $rc;
    my ($start, $stop) = ($self->start, $self->stop);
    if ($rc) 
      {
	$start -= $downstream;
	$stop += $upstream;
      }
    else
      {
	$start -= $upstream;
	$stop += $downstream;
      }

    $head .= " Genomic Location: $start-$stop";
    $Text::Wrap::columns=$col;
    my $fasta;
    if ($prot)
      {
	my $seq = $self->protein_sequence;
	if ($seq)
	  {
	    $seq = join ("\n", wrap("","",$seq)) if $col;
	    $fasta = $head."\n".$seq."\n";
	  }
	else
	  {
	    my ($seqs,$type) = $self->frame6_trans;
	    #check to see if we can find the best translation
	    my $found=0;
	    while (my ($k, $v) = each %$seqs)
	      {
		if (($v =~ /\*$/)|| $v !~ /\*/)
		  {
		    next if $v =~ /\*\w/;
		    $found = $k;
		  }
	      }
	    if ($found)
	      {
		$seq = $seqs->{$found};
		$seq = $self->reverse_complement($seq) if $rc;
		$seq = join ("\n", wrap("","",$seq)) if $col;
		$fasta .= $head;
		$fasta .= " $type frame $found" unless $name_only;
		$fasta .= "\n".$seq."\n";
	      }
	    else
	      {
		foreach my $frame (sort {CORE::length($a) <=> CORE::length($b) || $a cmp $b} keys %$seqs)
		  {
		    $seq = $seqs->{$frame};
		    $seq = $self->reverse_complement($seq) if $rc;
		    $seq = join ("\n", wrap("","",$seq)) if $col;
		    $fasta .= $head;
		    $fasta .= " $type frame $frame" unless $name_only;
		    $fasta .= "\n".$seq."\n";
		  }
	      }
	  }
      }
    else
      {
	my $seq = $self->genomic_sequence(upstream=>$upstream, downstream=>$downstream);
	$seq = $self->reverse_complement($seq) if $rc;
	$seq = join ("\n", wrap("","",$seq)) if $col;
	$fasta = $head."\n".$seq."\n";
	return $head, $seq if ($sep);
      }
    return $fasta;
  }

 

################################################ subroutine header begin ##

=head2 

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 
           : 

See Also   : 

=cut

################################################## subroutine header end ##

1;
