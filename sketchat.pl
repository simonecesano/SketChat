use Mojolicious::Lite -signatures;
use Mojo::Pg;
use Mojo::Util qw/md5_sum/;
use Mojo::JSON qw/encode_json decode_json/;
use Text::MultiMarkdown qw/markdown/;

app->plugin('Config');
push @{app->static->paths}, './static';

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://chat_user@/sketchat') };

get '/js/*jspath' => sub {
    my $c = shift;
    my $template = $c->param('jspath') =~ s/\.js$//r;
    $c->render( template => $template, format => 'js' );
};

get '/static/*filepath' => sub {
    my $c = shift;
    $c->reply->static($c->param('filepath'));
};

get '/' => sub {
    my $c = shift;
    $c->render( template => 'create_room' );
};

get '/canvas/:roomid' => sub {
    my $c = shift;
    
    $c->session('roomid', $c->param('roomid'));
    $c->session('signature', md5_sum(join '', time, int(rand * 1000))) unless $c->session('signature');

    $c->res->cookies({ name => 'signature', value => $c->session('signature') } );
    $c->render( template => 'canvas' );
};

get '/chat/:roomid' => sub {
    my $c = shift;
    $c->session('roomid', $c->param('roomid'));
    $c->render( template => 'chat' );
};

get '/messages' => sub {
    my $c = shift;
    if ($c->session('roomid')) {
	my $all = $c->pg->db->select('events', undef, { room_id => $c->session('roomid') })->hashes;
	$c->render( json => $all );
    } else {
	$c->render( json => [] );
    }
};

get '/messages/:nr' => sub {
    my $c = shift;
    if ($c->session('roomid')) {
	my $all = $c->pg->db->select('events', undef, { room_id => $c->session('roomid'), event_id => $c->param('nr') })->hash;
	$c->render( json => $all );
    } else {
	$c->render( json => undef );
    }
};


post '/messages/invalid' => sub {
    my $c = shift;
    if ($c->session('roomid') && $c->param('id')) {
	$c->app->log->info($c->session('roomid'), $c->param('id'));
	$c->pg->db->delete('events', { room_id => $c->session('roomid'), event_id => $c->param('id') });
	$c->render(json => { status => 'ok' });
    }
};



get '/login' => sub {
    my $c = shift;
    $c->app->log->info($c->flash('error'));

    $c->render('template' => 'login');
};

post '/login' => sub {
    my $c = shift;

    unless ($c->param('user') && $c->param('password')) {
	$c->flash('error', 'The id or the password are missing');
	return $c->redirect_to('/login');	    
    }
    
    my $url = Mojo::URL->new($c->app->config->{ews});
    $url->userinfo(join ':', $c->param('user'), $c->param('password'));
    my $xml = $c->render_to_string(template => "user", format => "xml");
    my $tx = $c->ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);

    if ($tx->res->is_success) {
	if ($tx->res->dom->at('ResponseCode')->all_text eq 'NoError') {
	    my $name  = $tx->res->dom->at('GivenName')->all_text;       $c->session('name', $name);
	    my $email = lc $tx->res->dom->at('EmailAddress')->all_text; $c->session('email', $email);
	    return $c->redirect_to('/');
	} else {
	    $c->flash('error', 'Wrong id or password');
	    return $c->redirect_to('/login');	    
	}
    } else {
	if ($tx->res->code == 401) {
	    $c->flash('error', "Wrong id or password");
	} else {
	    $c->flash('error', "Sorry there was an error - that's all we know");
	}
	return $c->redirect_to('/login');	    
    }
};



get '/help' => sub {
    my $c = shift;

    my $text = $c->render_to_string('help/index', format => 'txt');
    $c->stash('help_content', markdown("$text"));
    $c->render( template => 'help' );
};

websocket '/channel' => sub ($c) {

    $c->inactivity_timeout(36000);
    
    # Forward messages from the browser to PostgreSQL
    $c->on(message => sub ($c, $message) {
	       $c->app->log->info($message);
	       # $c->app->log->info($c->session('roomid'));
	       my $channel = 'mojochat::' . $c->session('roomid');
	       $c->app->log->info('message length', length $message);
	       $c->app->log->info('message', $message);
	       $message = decode_json($message);

	       if ($message->{alive}) {
		   $message->{signature} = $c->session('signature');
		   $message->{alive} = $c->session('email') || 'anonymous';
		   $message = encode_json($message);
		   $c->pg->pubsub->notify($channel => $message);
	       } elsif (defined $message->{retrieve}) {
		   
	       } else {
		   $c->app->log->info('email', $c->session('email'));
		   
		   $message->{signature} = $c->session('signature');
		   $message = encode_json($message);

		   $c->app->log->info('inserting');
		   $c->pg->db->insert('events', { event  => $message, room_id => $c->session('roomid'), user_id => $c->session('email'), event_time => time });
		   $c->pg->pubsub->notify($channel => $message);
	       }
	   });
    
    # Forward messages from PostgreSQL to the browser
    my $cb = sub ($pubsub, $message) {
	# $c->app->log->info($c->session('roomid'));
	$c->send($message)
    };


    $c->app->log->info($c->session('roomid'));
    my $channel = 'mojochat::' . $c->session('roomid');
    $c->pg->pubsub->listen($channel => $cb);
    
    # Remove callback from PG listeners on close
    $c->on(finish => sub ($c, @) {
	       # $c->app->log->info($c->session('roomid'));
	       
	       my $channel = 'mojochat::' . $c->session('roomid');

	       $c->pg->pubsub->unlisten($channel => $cb);
	   });
};

app->start;
__DATA__
