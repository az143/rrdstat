# main application class plus router class in one file
# this will setup the few routes we have
# / -> overview
# /item -> details for this item
# plus statics as needed for the images
package Mrrd;
use Mojo::Base 'Mojolicious';

# called once on startup
sub startup 
{
    my ($self) = @_;
    
    # not using any cookies, so a new internal secret every startup is peachy.
    $self->secrets([ rand(100000) ]);

    # set up our defaults: where are the graphs, rrdfiles, when to regen
    # end up in stash
    $self->defaults({ imgloc => "/img", # relative to public
		      imgdir => $self->home->rel_dir('/public/img'), # actual path

		      rrddir => "/var/lib/rrd",
		      maxage => 15*60,
		      # long list of section-thingie definitions, see example in config/
		      # returns hashref
		      sections => do "/etc/mrrd_sections.conf",
		    });

    my $r = $self->routes;
    # overview and details, that's all
    $r->get('/')->to(controller=>"Dinky",action=>"overview")->name("home");
    $r->get("/:object/:type/")->to(controller=>"Dinky",action=>"details");
}

1;

# the tiny controller class, which defines the two actions we deal with
package Mrrd::Dinky;
use Mojo::Base qw(Mojolicious::Controller);
use rrdimage;


# create the overview page
sub overview
{
    my ($self)=@_;

    $self->render_not_found if ($self->stash("format")); # format restricting in the route doesn't seem to work.

    # regeneration is forced for shift-reloads
    my $ccontrol=$self->req->headers->cache_control;
    $self->stash("forceregen"=>1) if (defined $ccontrol && $ccontrol eq "no-cache");

    my %rendersections=%{ $self->stash("sections") };;
    # walk the sections, run rrdimage_update, and feed the result to the overview template
    for my $sname (@{$rendersections{_order}})
    {
	for my $entity (@{$rendersections{$sname}})
	{
	    # run rrdimage update
	    # params include: the stashed defaults, the entity info and the mode
	    my ($errormsg,$imgname,$x,$y)=rrdimage::rrdimage_update(%{$self->stash}, mode=>"overview", %{$entity});
	    $entity->{error}=$errormsg;
	    $entity->{x}=$x;
	    $entity->{y}=$y;

	    $entity->{imgurl} = $self->url_for($self->stash("imgloc")."/$imgname")->to_string;
	    $entity->{detailurl} = $self->url_for("/$entity->{name}/$entity->{type}/")->to_string;
	}
    }
    $self->stash(rendersections => \%rendersections);
    # render overview template
    $self->res->headers->cache_control('max-age='.$self->stash("maxage"));
    $self->render(template=>"/index",layout=>"default");
}

# create the details page for one object+type
# stashed object+type indicate which object to work on
sub details
{
    my ($self)=@_;
    $self->render_not_found if ($self->stash("format")); # format restricting in the route doesn't seem to work.

    # regeneration is forced for shift-reloads
    my $ccontrol=$self->req->headers->cache_control;
    $self->stash("forceregen"=>1) if (defined $ccontrol && $ccontrol eq "no-cache");

    # find the relevant remaining parameters from the section list
    my $entity;
    my $object=$self->param("object");
    my $type=$self->param("type");

  LOOPER: 
    for my $sname (@{$self->stash("sections")->{_order}})
    {
	for my $e (@{$self->stash("sections")->{$sname}})
	{
	    if ($e->{name} eq $object and $e->{type} eq $type)
	    {
		$entity=$e;
		last LOOPER;
	    }
	}
    }
    $self->render_not_found  if (!$entity);
	

    $self->stash(title => "$object $type");
    for my $mode (qw(day week month year))
    {
	my ($errormsg,$imgname,$x,$y)=rrdimage::rrdimage_update(%{$self->stash}, mode=>$mode, %{$entity});
	$self->stash($mode => $self->url_for($self->stash("imgloc")."/$imgname")->to_string);
    }
    # render details template
    $self->res->headers->cache_control('max-age='.$self->stash("maxage"));
    $self->render(template=>"/details", layout=>"default");
}

1;


