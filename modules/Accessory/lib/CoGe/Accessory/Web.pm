package CoGe::Accessory::Web;

use strict;
use CoGe::Genome;
use CoGeX;
use Data::Dumper;
use base 'Class::Accessor';
use CGI::Carp('fatalsToBrowser');
use CGI;
use DBIxProfiler;
use File::Basename;
use File::Temp;

BEGIN {
    use Exporter ();
    use vars qw ($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $coge $Q $cogex $TEMPDIR);
    $VERSION     = 0.1;
    $TEMPDIR = "/opt/apache/CoGe/tmp";
    @ISA         = (@ISA, qw (Exporter));
    #Give a hoot don't pollute, do not export more than needed by default
    @EXPORT      = qw (login write_log read_log check_taint check_filename_taint save_settings load_settings reset_settings initialize_basefile);
    @EXPORT_OK   = qw ();
    %EXPORT_TAGS = ();
    $coge = new CoGe::Genome;
    $cogex = CoGeX->dbconnect();
#    $cogex->storage->debugobj(new DBIxProfiler());
#    $cogex->storage->debug(1);
    __PACKAGE__->mk_accessors qw(restricted_orgs basefilename basefile logfile sqlitefile);
 }


sub feat_name_search
  {
    my ($self, $accn, $num, $min_search) = self_or_default(@_);
    #may want to extend this function to use all the options of feat->power_search.  See FeatView.pl for an example
    $num = 1 unless defined $num;
    $min_search = 2 unless defined $min_search;
    return unless $accn;
    my $blank = qq{<input type="hidden" id="accn_select$num">};
#    print STDERR Dumper @_;
    return $blank unless length($accn) > $min_search;# || $type || $org;
    my $html;
    my %seen;
    my @opts = sort map {"<OPTION>$_</OPTION>"} grep {! $seen{$_}++} map {uc($_)} $coge->get_feature_name_obj->power_search(accn=>$accn."%");
    if (@opts > 5000)
      {
	return $blank."Search results over 1000, please refine your search.\n";
      }
    $html .= "<font class=small>Name count: ".scalar @opts."</font>\n<BR>\n";
    $html .= qq{<SELECT id="accn_select$num" SIZE="5" MULTIPLE onChange="source_search_chain(); " >\n};
    $html .= join ("\n", @opts);
    $html .= "\n</SELECT>\n";
    $html =~ s/<OPTION/<OPTION SELECTED/;
    return $blank."No results found.\n", $num unless $html =~ /OPTION/;
    return $html, $num;
  }

sub dataset_search_for_feat_name
  {
    my ($self, $accn, $num, $dsid, $featid) = self_or_default(@_);
    $num = 1 unless $num;
    return ( qq{<input type="hidden" id="dsid$num">\n<input type="hidden" id="featid$num">}, $num )unless $accn;
    my $html;
    my %sources;
    my %restricted_orgs = %{$self->restricted_orgs} if $self->restricted_orgs;
    my $rs = $cogex->resultset('Dataset')->search(
						  {
						   'feature_names.name'=> $accn,
						  },
						  {
						   'join'=>{
							    'features' => 'feature_names',
							   },
							    
						   'prefetch'=>['datasource', 'organism'],
						  }
						 );
    while (my $ds = $rs->next())
      {
	my $name = $ds->name;
	my $ver = $ds->version;
	my $desc = $ds->description;
	my $sname = $ds->datasource->name;
	my $ds_name = $ds->name;
	my $org = $ds->organism->name;
	my $title = "$org: $ds_name ($sname, v$ver)";
	next if $restricted_orgs{$org};
	$sources{$ds->id} = {
			     title=>$title,
			     version=>$ver,
			    };
      }
     if (keys %sources)
       {
 	$html .= qq{
 <SELECT name = "dsid$num" id= "dsid$num" onChange="feat_search(['accn$num','dsid$num', 'args__$num'],['feat$num']);" >
 };
 	foreach my $id (sort {$sources{$b}{version} <=> $sources{$a}{version}} keys %sources)
 	  {
 	    my $val = $sources{$id}{title};
 	    $html  .= qq{  <option value="$id"};
	    $html .= qq{ selected } if $dsid && $id == $dsid;
	    $html .= qq{>$val\n};
 	  }
 	$html .= qq{</SELECT>\n};
 	my $count = scalar keys %sources;
 	$html .= qq{<font class=small>($count)</font>};
       }
     else
       {
 	$html .= qq{Accession not found <input type="hidden" id="dsid$num">\n<input type="hidden" id="featid$num">\n};	
       }    
    return ($html,$num);
  }

sub feat_search_for_feat_name
  {
    my ($self, $accn, $dsid, $num) = self_or_default(@_);
    return qq{<input type="hidden" id="featid$num">\n} unless $dsid;
    my @feats;
    my $rs = $cogex->resultset('Feature')->search(
						  {
						   'feature_names.name'=> $accn,
						   'dataset.dataset_id' => "$dsid",
						  },
						  {
						   'join'=>['feature_type','dataset', 'feature_names'],
						   'prefetch'=>['feature_type', 'dataset'],
						  }
						 );
    my %seen;
    while( my $f =$rs->next())
      {
	next unless $f->dataset->id == $dsid;
#	next if $f->feature_type->name =~ /CDS/i;
#	next if $f->feature_type->name =~ /RNA/i;
	push @feats, $f unless $seen{$f->id};
	$seen{$f->id}=1;
      }
    my $html;
    if (@feats)
      {
	$html .= qq{
<SELECT name = "featid$num" id = "featid$num" >
  };
	foreach my $feat (sort {$a->type->name cmp $b->type->name} @feats)
	  {
	    my $loc = "(".$feat->type->name.") Chr:".$feat->locations->next->chromosome." ".$feat->start."-".$feat->stop;
	    #working here, need to implement genbank_location_string before I can progress.  Need 
	    $loc =~ s/(complement)|(join)//g;
	    my $fid = $feat->id;
	    $html .= qq {  <option value="$fid">$loc \n};
	  }
	$html .= qq{</SELECT>\n};
	my $count = scalar @feats;
	$html .= qq{<font class=small>($count)</font>};
      }
    else
      {
	$html .=  qq{<input type="hidden" id="featid$num">\n}
      }
    return $html;
  }

sub type_search_for_feat_name
  {
    my ($accn, $dsid, $num) = self_or_default(@_);
    $num = 1 unless defined $num;
    my $html;
    my $blank = qq{<input type="hidden" id="type_name$num">};
    my %seen;
    my @opts = sort map {"<OPTION>$_</OPTION>"} grep {! $seen{$_}++} map {$_->type->name} $coge->get_features_by_name_and_dataset_id(name=>$accn, id=>$dsid);
    $html .= "<font class=small>Type count: ".scalar @opts."</font>\n<BR>\n";
    $html .= qq{<SELECT id="Type_name" SIZE="5" MULTIPLE onChange="get_anno(['accn_select$num','type_name$num', 'dsid$num'],['anno$num'])" >\n};
    $html .= join ("\n", @opts);
    $html .= "\n</SELECT>\n";
    $html =~ s/OPTION/OPTION SELECTED/;
    return $blank unless $html =~ /OPTION/;
    return ($html, 1, $num);
  }

sub feat_name_search_box
  {
    my ($self, $num, $default) = self_or_default(@_);
    $num = 1 unless defined $num;
    return qq{
<input type="text" name="accn$num" id="accn$num" tabindex="1"  size="10" onKeyup ="feat_name_search_chain(0);"  onBlur="feat_name_search_chain(1);" value="$default"/>
<DIV class="" id="accn_list$num"><input type="hidden" id="accn_select$num" ></DIV>
<DIV class="" id="ds$num"></DIV>
<DIV class="" id="feat_type$num"></DIV>
<DIV class="" id="anno$num"></DIV>
};
  }

sub feat_search_box
  {
    my ($self, $num, $default) = self_or_default(@_);
    $num = 1 unless defined $num;
    return qq{
<input class="backbox" type="text" name="accn$num" id="accn$num" tabindex="$num"  size="20" onBlur="dataset_search(['accn$num','args__$num'],[feat_search_chain])" value="$default" />
<DIV id="ds$num"><input type="hidden" id="dsid$num"></DIV>
<DIV id="feat$num"><input type="hidden" id="featid$num"></DIV>
};
  }

sub feat_name_search_chain
  {
    my ($self, $lim) = self_or_default(@_);
    $lim = 4 unless defined $lim;
    return qq{
<SCRIPT language="javascript">
function feat_name_search_chain(val, num) {
 if (!num) {num = 1};
 minlen = $lim;
 if ((val == 1) && (kaj.GS('accn'+num).length > minlen)){
   return;
 } 
 kaj.GS('accn_list'+num,'fnsc_accn_list'+num);	
 kaj.GS('ds'+num,'fnsc_ds'+num);	
 kaj.GS('feat_type'+num,'fnsc_feat_type'+num);	
// kaj.GS('anno'+num,'');	
 if (val == 1 || kaj.GS('accn'+num).length > minlen) {
//   kaj.GS('DS_title','<font class="loading">Searching. . .</font>');// for "'+kaj.GS('accn')+'" type '+''+'. . .</font>');
   feat_name_search(['accn'+num, 'args__'+num],[ds_search_chain]); 
 }
}
</SCRIPT>
};
  }

sub ds_search_chain
  {
return qq{
<SCRIPT language="javascript">
function ds_search_chain (val, num) {
 kaj.GS('ds'+num,'<font class="loading">dssc_ds'+num+'Loading. . .</font>');	
 kaj.GS('feat_type'+num,'dssc_feat_type'+num);
 kaj.GS('anno'+num,'dssc_anno'+num);
 if (val) {kaj.GS('accn_list'+num,val);}
 dataset_search(['accn_select'+num, 'args__'+num], [feat_type_search_chain]);
}
</SCRIPT>

};

  }

sub feat_search_chain
  {
    return qq{
<SCRIPT language="javascript">
function feat_search_chain(val, num) {
 if (val) {
  kaj.GS('ds'+num, val);
  feat_search(['accn'+num,'dsid'+num, 'args__'+num],['feat'+num]);
 }
}
</SCRIPT>
};
  }

sub feat_type_search_chain
  {
    return qq{
<SCRIPT language="javascript">
function feat_type_search_chain (val1, num) {
// kaj.GS('FT_title','');
 kaj.GS('feat_type'+num,'<font class="loading">FTC_feat_type Loading. . .</font>');	
 kaj.GS('anno'+num,'FTC_anno');	
 if (val1) {kaj.GS('ds'+num, val1);}
// if (val2) {kaj.GS('DS_title', "Dataset");}	
 type_search(['accn_select'+num, 'dsid'+num, 'args__'+num],[get_anno_chain]);	
}
</SCRIPT>
};
}

sub kaj
  {
    return qq{
<SCRIPT language="JavaScript" type="text/javascript" src="./js/kaj.stable.js"></SCRIPT>
};
  }

sub self_or_default { #from CGI.pm
    return @_ if defined($_[0]) && (!ref($_[0])) &&($_[0] eq 'CoGe::Accessory::Web');
    unless (defined($_[0]) && 
            (ref($_[0]) eq 'CoGe::Accessory::Web' || UNIVERSAL::isa($_[0],'CoGe::Accessory::Web')) # slightly optimized for common case
            ) {
        $Q = CoGe::Accessory::Web->new unless defined($Q);
        unshift(@_,$Q);
    }
    return wantarray ? @_ : $Q;
}

sub login
  {
    my $form = new CGI;
    my $url = "index.pl?url=".$form->url(-relative=>1, -query=>1);
#    print STDERR $url;
    $url =~ s/&|;/:::/g;
    my $html1 = qq{
<SCRIPT language="JavaScript">
window.location=$url;
</SCRIPT>
};
    my $html = qq{
<html>
<head>
<title>CoGe:  the best program of its kind, ever.</title>
<meta http-equiv="REFRESH" content="1;url=$url"></HEAD>
<BODY>
You are not logged in.  You will be redirected to <a href = $url>here</a> in one second.
</BODY>
</HTML>
};
    return $html;
  }

sub ajax_func
  {
    return 
      (
       dataset_search=>\&dataset_search_for_feat_name,
       feat_search=>\&feat_search_for_feat_name,
       feat_name_search=>\&feat_name_search,
       type_search=> \&type_search_for_feat_name,
       login=>\&login,
       read_log=>\&read_log,
       initialize_basefile=>\&initialize_basefile,
      );
  }

sub write_log
  {
    $| = 1;
    my $message = shift;
    $message =~ /(.*)/;
    $message = $1;
    my $file = shift;
    return unless $file;
    open (OUT, ">>$file") || return;
    print OUT $message,"\n";
    close OUT;
  }

sub read_log
  {
    my %args = @_;
    my $logfile = $args{logfile};
    my $prog = $args{prog};
#    print STDERR "Checking logfile $logfile\n";
    return unless $logfile;
    $logfile .= ".log" unless $logfile =~ /log$/;
    $logfile = $TEMPDIR."/$prog/$logfile" unless $logfile =~ /^$TEMPDIR/;
    return unless -r $logfile;
    my $str;
    open (IN, $logfile);
    while (<IN>)
      {
	$str .= $_;
      }
    close IN;
    return $str;
  }

sub check_filename_taint {
  my $v = shift;
  return 1 unless $v;
  if ($v =~ /^([A-Za-z0-9\-\.=\/_]*)$/) {
    my $v1 = $1;
    return($v1);
  } else {
    return(0);
  }
}

sub check_taint {
  my $v = shift;
  return 1 unless $v;
  if ($v =~ /^([-\w._=\s+\/]+)$/) {
    $v = $1;
    # $v now untainted
    return(1,$v);
  } else {
    # data should be thrown out
    carp "'$v' failed taint check\n";
    return(0);
  }
}

sub save_settings
  {
    my %opts = @_;
    my $user = $opts{user};
    my $user_id = $opts{user_id};
    my $page = $opts{page};
    my $opts = $opts{opts};
    unless ($user_id)
      {
	my ($user_obj) = $cogex->resultset('User')->search({user_name=>$user});
	$user_id = $user_obj->id if $user_obj;
      }
    return unless $user_id;
    #delete previous settings
    foreach my $item ($cogex->resultset('WebPreferences')->search({user_id=>$user_id, page=>$page}))
      {
	$item->delete;
      }
    my $item = $cogex->resultset('WebPreferences')->new({user_id=>$user_id, page=>$page, options=>$opts});
    $item->insert;
    return $item;
  }

sub load_settings
  {
    my %opts = @_;
    my $user = $opts{user};
    my $user_id = $opts{user_id};
    my $page = $opts{page};
    unless ($user_id)
      {
	my ($user_obj) = $cogex->resultset('User')->search({user_name=>$user});
	$user_id = $user_obj->id if $user_obj;
      }
    return {} unless $user_id;
    my ($item) = $cogex->resultset('WebPreferences')->search({user_id=>$user_id, page=>$page});
    return {} unless $item;
    my $prefs;
    my $opts = $item->options if $item;
    return {} unless $opts;
    $opts =~ s/VAR1/prefs/;
    eval $opts;
    return $prefs;
  }

sub reset_settings
  {
    my %opts = @_;
    my $user = $opts{user};
    my $user_id = $opts{user_id};
    my $page = $opts{page};
    unless ($user_id)
      {
	my ($user_obj) = $cogex->resultset('User')->search({user_name=>$user});
	$user_id = $user_obj->id if $user_obj;
      }
    return unless $user_id;
    my ($item) = $cogex->resultset('WebPreferences')->search({user_id=>$user_id, page=>$page});
    $item->delete;
  }

sub initialize_basefile
  {
    my ($self, %opts) = self_or_default(@_);
    my $basename = $opts{basename};
    my $prog=$opts{prog} || "CoGe";
    my $return_name = $opts{return_name};
    if ($basename)
      {
#	print STDERR "Have basename: $basename\n";
	($basename) = $basename =~ /([^\/].*$)/;
	my ($x, $cleanname) = check_taint($basename);
	$self->basefilename($cleanname);
	$self->basefile($TEMPDIR."/$prog/".$cleanname);
	$self->logfile($self->basefile.".log");
	$self->sqlitefile($self->basefile.".sqlite");
      }
    else
      {
	mkdir "$TEMPDIR/$prog",0777 unless -d "$TEMPDIR/$prog";
	my $file = new File::Temp ( TEMPLATE=>$prog.'_XXXXXXXX',
				    DIR=>"$TEMPDIR/$prog/",
				    #SUFFIX=>'.png',
				    UNLINK=>1);
	$self->basefile($file->filename);
	$self->logfile($self->basefile.".log");
	$self->sqlitefile($self->basefile.".sqlite");
	$self->basefilename($file->filename =~ /([^\/]*$)/)
      }
#    print STDERR "Basename: ",$self->basefilename,"\n";
#    print STDERR "sqlitefile: ",$self->sqlitefile,"\n";
#    print STDERR "Basefile: ",$self->basefile,"\n";

    if ($return_name)
      {
	return $self->basefilename;
      }
    else {return $self;}
  }

1;
