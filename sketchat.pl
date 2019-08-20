use Mojolicious::Lite -signatures;
use Mojo::Pg;

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://chat_user@/sketchat') };

get '/room' => sub {
    my $c = shift;
    $c->render( template => 'create_room' );
};

get '/canvas/:roomid' => sub {
    my $c = shift;
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


websocket '/channel' => sub ($c) {
    $c->inactivity_timeout(3600);
    
    # Forward messages from the browser to PostgreSQL
    $c->on(message => sub ($c, $message) {
	       # $c->app->log->info($message);
	       # $c->app->log->info($c->session('roomid'));

	       my $channel = 'mojochat::' . $c->session('roomid');

	       $c->pg->db->insert('events', { event  => $message, room_id => $c->session('roomid'), event_time => time });
	       $c->pg->pubsub->notify($channel => $message);
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
