package Flickr::Simple2;

use 5.008000;
use strict;
use warnings;

our $VERSION = '0.02';

use Carp;
use Digest::MD5 qw(md5_hex);
use Iterator::Simple qw(iterator);
use LWP::Simple;
use URI;
use XML::Simple;

=head1 NAME

Flickr::Simple2 - A XML::Simple based Perl Flickr API. 

=head1 SYNOPSIS

  use Flickr::Simple2;
  my $flickr =
    Flickr::Simple2->new({
        api_key => $cfg->param('Flickr.API_KEY'),
        api_secret => $cfg->param('Flickr.API_SHARED_SECRET'),
        auth_token => $cfg->param('Flickr.auth_token')
    });

=head1 DESCRIPTION

A XML::Simple based Perl Flickr API. 

=head2 EXPORT

None by default.

=cut

=head1 METHODS

=head2 new

=over 4

my $flickr = Flickr::Simple2->new({
        api_key => $cfg->param('Flickr.API_KEY'),
        api_secret => $cfg->param('Flickr.API_SHARED_SECRET'),
        auth_token => $cfg->param('Flickr.auth_token')
    });

 api_key is your Flickr API key given by Flickr api_secret is your Flickr API secret key given by Flickr.  It is used to sign certain Flickr API methods

 auth_token is optional for public/safe access to photos but is required for nonsafe/private photos or any Flickr API method requiring authentication

=back

=cut

sub new {    
    my $proto = shift;
    my $params_ref = shift;
    
    my $class = ref($proto) || $proto;

    my $self = {};
    
    %{ $self->{params} } = map { $_ => $params_ref->{$_} } keys %$params_ref;
    
    bless ($self, $class);
    return $self;
}

sub NEXTVAL {
    $_[0]->();
}

#-------------------------------------

=head2 request

=over 4

An internal Flickr::Simple2 method used to communicate with the Flickr REST service.  It uses XML::Simple for parsing of the XML data.

=back

=cut

sub request {
    my $self = shift;
    my ($flickr_method, $args, $xml_simple_args) = @_;
    
    $xml_simple_args = {} unless $xml_simple_args;
    
    my $uri;
    my @flickr_args = ('method', $flickr_method, 'api_key', $self->{params}->{api_key});
    
    foreach my $key (sort { lc $a cmp lc $b } keys %$args) {
      push( @flickr_args, ($key, $args->{$key}) ) if defined $args->{$key};
    }
    
    $uri = URI->new('http://api.flickr.com/services/rest');
    $uri->query_form(\@flickr_args);
    my $content = get($uri);

    if ($content) {
        my $response = XMLin($content, %$xml_simple_args);
        return $response if $response;
    }
}

#------------------------------

#------------------------------

=head2 echo

=over 4

$echo_ref = $flickr->echo({ wild => "and crazy guy"});

 A simple method to send a message to Flickr and receive it back as a hash reference.

 Requires: hash reference containing valid name/value pairs, api_key
 Returns: hash reference containing the response from Flickr

=back

=cut

sub echo {
    my $self = shift;
    my $args = shift;

    return unless ($args);

    my $response = $self->request('flickr.test.echo', $args, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        my %echo = map { $_ => $response->{$_} }
            grep { ! /^(?:method|api_key|stat)$/ } keys %$response;
        return \%echo;
    } else {
        $self->raise_error($response, 'echo', 1);
        return;
    }
}

#------------------------------

=head2 raise_error

=over 4

$self->raise_error($response, 'echo', 1);
 
 An internal method that sets the simple error object hash reference.  The hash ref will be undefined if no error exists.  

=back

=cut

sub raise_error {
    my $self = shift;
    my ($response, $calling_sub, $exit_now) = @_;

    if (defined $response->{err}) {
        $self->{'error'} = { calling_sub => $calling_sub, message => $response->{err}->{msg}, code => $response->{err}->{code} };
    }
}

#------------------------------

=head2 flickr_sign

=over 4

$self->flickr_sign({ method => 'flickr.auth.getFrob'});

 An internal method to sign the Flickr API method call with your Flickr API secret key.

 Requires: arguments to sign, flickr_api and flickr_api_secret
 Returns: String containing the signed arguments

=back

=cut

sub flickr_sign {
    my $self = shift;
    my $flickr_hash_ref = shift;

    if ( $self->{params}->{api_secret} ) {
        my $sign = $self->{params}->{api_secret};
        $flickr_hash_ref->{api_key} = $self->{params}->{api_key};

        foreach my $arg (sort { $a cmp $b } keys %{$flickr_hash_ref}) {
            if ( defined($flickr_hash_ref->{$arg}) ) {
                $sign .= $arg . $flickr_hash_ref->{$arg};
            } else {
                $sign .= $arg . "";
            }
        }

        return md5_hex($sign);
    }
}

#------------------------------

=head2 get_auth_frob

=over 4

my $frob = $flickr->get_auth_frob();

 A method to retrieve a Flickr frob, used for authentication.

 Requires: api_key and api_secret
 Returns: String containing the frob  

=back

=cut

sub get_auth_frob {
    my $self = shift; 

    my $sign = $self->flickr_sign({ method => 'flickr.auth.getFrob'});
    my $response = $self->request('flickr.auth.getFrob', { api_sig => $sign }, { forcearray => 0, keeproot => 0 });
        
    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $response->{frob};
    } else {
        $self->raise_error($response, 'main', 1);
        return;
    }               
}

=head2 get_auth_url

=over 4

my $auth_url = $flickr->get_auth_url($frob, 'read');

 A method to retrieve the url (webpage) for a Flickr user to authorize your application to use their account.

 Requires: frob, permissions (read/write), api_key and api_secret
 Returns: String containing the URL

=back

=cut

sub get_auth_url {
    my $self = shift;
    my ($frob, $permissions) = @_;

    if ($frob && $permissions) {
        my $uri;
        my %args = (
          'frob'    => $frob,
          'perms'   => $permissions
        );
    
        $args{api_sig} = $self->flickr_sign({ frob => $frob, perms => $permissions});
        $args{api_key} = $self->{params}->{api_key};
        
        $uri = URI->new('http://flickr.com/services/auth');
        $uri->query_form(%args);
        return $uri;
    }
}

=head2 get_auth_token

=over 4

my $auth_token = $flickr->get_auth_token($frob);

 A method to retrieve a Flickr authorization token.  Called after a user authorizes your application with the url returned from get_auth_url().

 Requires: frob, api_key and api_secret
 Returns: String containing the authorization token
 
=back

=cut

sub get_auth_token {
    my $self = shift;
    my $frob = shift;

    my $sign = $self->flickr_sign({ frob => $frob, method => 'flickr.auth.getToken'});
    my $response = $self->request('flickr.auth.getToken', { api_sig => $sign, frob => $frob }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{params}->{'auth_token'} = $response->{'auth'}->{'token'};
        $self->{error} = undef;
        return $response->{'auth'}->{'token'};
    } else {
        $self->raise_error($response, 'get_auth_token', 1);
        return;
    }  
}

=head2 check_auth_token

=over 4

my $auth = $flickr->check_auth_token()

 A method to validate a Flickr auth_token.

 Requires: auth_token, api_key and api_secret
 Returns: true (1) if auth_token is valid else undef

=back

=cut

sub check_auth_token {
    my $self = shift;

    my $sign = $self->flickr_sign({ auth_token => $self->{params}->{auth_token}, method => 'flickr.auth.checkToken'});
    my $response = $self->request('flickr.auth.checkToken', { api_sig => $sign, auth_token => $self->{params}->{auth_token} }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
       $self->{error} = undef;
       return 1;
    } else {
        $self->raise_error($response, 'check_auth_token', 1);
        return undef;
    } 
}

#------------------------------

=head2 get_user_byEmail

=over 4

my $user_nsid = $flickr->get_user_byEmail('jason_froebe@yahoo.com');

 Retrieves the NSID of a Flickr user when given an email address

 Requires: email address, api_key
 Returns: String containing the NSID of the user

=back

=cut

sub get_user_byEmail {
    my $self = shift;
    my $user_email = shift;

    my $response = $self->request('flickr.people.findByEmail', { find_email => $user_email }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $self->get_user_info( $response->{user}->{nsid} );
    } else {
        $self->raise_error($response, 'get_user_byEmail', 1);
        return;
    }
}

=head2 get_user_byUsername

=over 4

my $user_nsid = $flickr->get_user_byUserName('jason_froebe');

 Retrieves the NSID of a Flickr user when given a Flickr username

 Requires: Flickr username, api_key
 Returns: String containing the NSID of the user

=back

=cut

sub get_user_byUserName {
    my $self = shift;
    my $username = shift;

    my $response = $self->request('flickr.people.findByUsername', { username => $username }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $self->get_user_info( $response->{user}->{nsid} );
    } else {
        $self->raise_error($response, 'get_user_byUserName', 1);
        return;
    }
}

=head2 get_user_byURL

=over 4

my $user_nsid = $flickr->get_user_byURL('http://www.flickr.com/photos/jfroebe/3214186886/');

 Retrieves the NSID of a Flickr user when given any URL (from Flickr website) associated with the user

 Requires:  URL, api_key
 Returns: String containing the NSID of the user

=back

=cut

sub get_user_byURL {
    my $self = shift;
    my $url = shift;

    my $response = $self->request('flickr.urls.lookupUser', { url => $url }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $self->get_user_info( $response->{user}->{id} );
    } else {
        $self->raise_error($response, 'get_user_byUserName', 1);
        return;
    }
}

=head2 get_user_info

=over 4

my $user_info = $flickr->get_user_info($user_nsid)

 Retrieves extensive information regarding a Flickr user

 Requires: NSID, api_key
 Returns: Hash reference containing information about the user

=back

=cut

sub get_user_info {
    my $self = shift;
    my $nsid = shift;

    my $response = $self->request('flickr.people.getInfo', { user_id => $nsid }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $response->{person};
    } else {
        $self->raise_error($response, 'get_user_info', 1);
        return;
    }
}
#------------------------------

=head2 get_license_info

=over 4

Retrieves the types of licenses used at Flickr

 Requires: api_key
 Returns: Hash reference containing the license information

=back

=cut

sub get_license_info {
    my $self = shift;

    my $response = $self->request('flickr.photos.licenses.getInfo', undef, { forcearray => ['id'], keeproot => 0, keyattr => ['id'] });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $response->{licenses}->{license};
    } else {
        $self->raise_error($response, 'get_license_info', 1);
        return;
    }
}

#------------------------------

=head2 get_photo_exif

=over 4

$self->get_photo_exif($photo_id, $photo_secret);

 Retrieve the EXIF tags about a particular photo.  Primarily used by get_photo_detail but can be used separately

 Requires: photo id, photo secret and api_key
 Returns: Hash reference containing the EXIF tags  

=back

=cut

sub get_photo_exif {
    my $self = shift;
    my ($photo_id, $photo_secret) = @_;

    my $response = $self->request('flickr.photos.getExif', { photo_id => $photo_id, secret => $photo_secret }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        my $exif_ref;

        foreach my $hash_ref ( @{ $response->{photo}->{exif} }) {
            $exif_ref->{ $hash_ref->{tagspace} }->{ $hash_ref->{tag} } = $hash_ref->{raw};
        }

        $self->{error} = undef;
        return $exif_ref;
    } else {
        $self->raise_error($response, 'get_photo_detail', 1);
        return;
    }
}

=head2 get_photo_detail

=over 4

my $photo_detail = $flickr->get_photo_detail($photo_id, $public_photos->{photo}->{$photo_id}->{secret});

 Retrieves extensive information regarding a particular photo.

 Requires: photo id, photo secret, api_key
 Optional: api_secret for none safe/public photos
 Returns: Hash reference containing photo information

=back

=cut

sub get_photo_detail {
    my $self = shift;
    my ($photo_id, $photo_secret) = @_;

    my $response = $self->request('flickr.photos.getInfo', { photo_id => $photo_id, secret => $photo_secret }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        $response->{photo}->{exif} = $self->get_photo_exif($photo_id, $photo_secret);
        $response->{photo}->{tags} = $self->get_photo_tags($response->{photo}->{tags});
        $response->{photo}->{urls} = $self->build_photo_urls( $photo_id, $response->{photo} );
        return $response->{photo};
    } else {
        $self->raise_error($response, 'get_photo_detail', 1);
        return;
    }
}

=head2 get_public_photos_page

=over 4

my $photos_iterator = $self->get_public_photos_page($user, $params_ref);

 Retrieves a "page" of photos from Flickr. Flickr groups photos in pages similar to their website.  

 Returns: a hash reference for the current page of photos

=back

=cut

sub get_public_photos_page {
    my $self = shift;
    my ($user, $params_ref) = @_;

    my $max_pages = 1;

    if ($params_ref->{per_page}) {
        $max_pages = (int $user->{photos}->{count} / $params_ref->{per_page}) + 1;
    }

    my $args->{user_id} = $user->{nsid};

    if ($params_ref->{safe_search}) {
        if ($params_ref->{safe_search} eq 'safe') {
            $args->{safe_search} = 1;
        } elsif ($params_ref->{safe_search} eq 'moderate') {
            $args->{safe_search} = 2;
        } elsif ($params_ref->{safe_search} eq 'restricted') {
            $args->{safe_search} = 3;
        }
    }

    if ($params_ref->{extras}) {
        $args->{extras} = $params_ref->{extras};
    } else { 
        $args->{extras} = "license,date_upload,date_taken,owner_name,icon_server,original_format,last_update,geo,tags,machine_tags,o_dims,views,media";
    }
    
    $args->{per_page} = $params_ref->{per_page} if $params_ref->{per_page};
    
    if ($params_ref->{page}) {
        $args->{page} = $params_ref->{page};
    } else {
        $args->{page} = 1;
    }

    iterator {
        my $response = $self->request('flickr.people.getPublicPhotos', $args, { forcearray => 0, keeproot => 0 });
        
        unless (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
            $self->raise_error($response, 'get_public_photos', 1);
            return;
        }

        $args->{page}++ if ($args->{page} < $max_pages);
        return $response;
    }    
}


=head2 get_public_photos

=over 4

my $public_photos = $flickr->get_public_photos($user->{nsid}, { per_page => 3 });

 Retrieves a list of a Flickr user's public photos (simple info) 

 Requires: NSID, hash reference containing the number of photos (per page) to retrieve at a time
 Optional: Within the hash reference:  safe_search, extras and page of photos to return

 From Flickr API:
    safe_search (Optional)
        Safe search setting:
    
            * 1 for safe.
            * 2 for moderate.
            * 3 for restricted.
    
        (Please note: Un-authed calls can only see Safe content.)
    extras (Optional)
        A comma-delimited list of extra information to fetch for each returned record. Currently supported fields are: license, date_upload, date_taken, owner_name, icon_server, original_format, last_update, geo, tags, machine_tags, o_dims, views, media.
    per_page (Optional)
        Number of photos to return per page. If this argument is omitted, it defaults to 100. The maximum allowed value is 500.
    page (Optional)
        The page of results to return. If this argument is omitted, it defaults to 1.

 Returns: Hash reference containing photos and simple photo details (photo secret for example)

=back

=cut

sub get_public_photos {
    my $self = shift;
    my $user = shift;
    my $params_ref = shift;

    ${ $self->{licenses} } = $self->get_license_info() unless $self->{licenses};

    my $photos_iterator = $self->get_public_photos_page($user, $params_ref);

    $self->{error} = undef;
    my $photo_page = $photos_iterator->next;
    my @photo_ids = keys %{$photo_page->{photos}->{photo}};

    iterator {
        my $photo_id = shift @photo_ids;

        unless (defined $photo_id) {
            $photo_page = $photos_iterator->next;

            if (defined $photo_page) {
                @photo_ids = keys %{$photo_page->{photos}->{photo}};
                $photo_id = shift @photo_ids;
            }            
        }

        if (defined $photo_id) {
            $photo_page->{photos}->{photo}->{$photo_id}->{urls} 
                = $self->build_photo_urls( $photo_id, $photo_page->{photos}->{photo}->{$photo_id} );

            $photo_page->{photos}->{photo}->{$photo_id}->{photo_id} = $photo_id;

            return $photo_page->{photos}->{photo}->{$photo_id};
        }
    }
}

=head2 build_photo_urls

=over 4

my $photo_urls_ref = $self->build_photo_urls($photo_id, $response->{photos}->{photo}->{$photo_id} ) 

 From Flickr API:
    http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}.jpg
    http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}_[mstb].jpg
    http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{o-secret}_o.(jpg|gif|png)
        s	small square 75x75
        t	thumbnail, 100 on longest side
        m	small, 240 on longest side
        -	medium, 500 on longest side
        b	large, 1024 on longest side (only exists for very large original images)
        o	original image, either a jpg, gif or png, depending on source format

 An internal method that builds the various size photo URLs for a particular photo.  Called primarily from get_public_photos.  Does not guarantee that the photo URLs are valid.

 Requires: photo id, reference containing details of the photo, api_key
 Returns: Hash reference containing the photo URLs

=back

=cut

sub build_photo_urls {
    my $self = shift;
    my ($photo_id, $photo_ref) = @_;

    my $urls = {};

    my $base_url = sprintf "http://farm%s.static.flickr.com/%s/%s_",
        $photo_ref->{farm},
        $photo_ref->{server},
        $photo_id;

    $urls->{smallsquare} = sprintf "%s%s_s.jpg", $base_url, $photo_ref->{secret};
    $urls->{thumbnail} = sprintf "%s%s_t.jpg", $base_url, $photo_ref->{secret};
    $urls->{small} = sprintf "%s%s_m.jpg", $base_url, $photo_ref->{secret};
    $urls->{medium} = sprintf "%s%s.jpg", $base_url, $photo_ref->{secret};
    $urls->{large} = sprintf "%s%s_b.jpg", $base_url, $photo_ref->{secret};
    $urls->{original} = sprintf "%s%s_o.%s", $base_url, $photo_ref->{originalsecret}, $photo_ref->{originalformat};

    return $urls;
}

=head2 get_photo_sizes

=over 4

Retrieves photo size information regarding a particular photo.

 Requires: photo id, api_key
 Returns: Hash reference containing URLs and other information regarding the sizes of the photo

=back

=cut

sub get_photo_sizes {
    my $self = shift;
    my $photo_id = shift;

    my $url = {};
    my $response = $self->request('flickr.photos.getSizes', { photo_id => $photo_id }, { forcearray => 0, keeproot => 0 });

    if (defined $response->{'stat'} && $response->{'stat'} eq 'ok') {
        $self->{error} = undef;
        return $response->{sizes}->{size};
    } else {
        $self->raise_error($response, 'get_photo_sizes', 1);
        return;
    }
    return $url;
}

=head2 get_photo_tags

=over 4

$self->get_photo_tags($tags_ref);

 Sanitizes the tags structure that is part of the flickr.photos.getInfo response.  Used by get_photo_detail subroutine.

 Requires tags structure returned by flickr.photos.getInfo 
 Returns a hash ref with tag_name => "tagged by NSID" structure.

=back

=cut

sub get_photo_tags {
    my $self = shift;
    my $tags = shift;

    my $tmp_tags;

    foreach my $value (keys %{ $tags->{tag} }) {
        $tmp_tags->{ $tags->{tag}->{$value}->{content} } = $tags->{tag}->{$value}->{author};
    }

    return $tmp_tags;
}

#------------------------------
1;

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Jason L. Froebe, E<lt>jason@froebe.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Jason L. Froebe

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.08.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
