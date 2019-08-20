use Mojolicious::Lite -signatures;
use Mojo::Pg;

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://chat_user@/sketchat') };

get '/room' => sub {
    my $c = shift;
    $c->render( template => 'create_room' );
};

get '/canvas/:roomid' => sub {
    my $c = shift;
    $c->session('roomid', $c->param('roomid'));
    $c->render( template => 'canvas' );
};


get '/room/:roomid' => sub {
    my $c = shift;
    $c->session('roomid', $c->param('roomid'));
    $c->render( template => 'chat' );
};


websocket '/channel' => sub ($c) {
    $c->inactivity_timeout(3600);

    
    # Forward messages from the browser to PostgreSQL
    $c->on(message => sub ($c, $message) {
	       $c->app->log->info($message);
	       $c->app->log->info($c->session('roomid'));

	       my $channel = 'mojochat::' . $c->session('roomid');
	       
	       $c->pg->pubsub->notify($channel => $message);
	   });
    
    # Forward messages from PostgreSQL to the browser
    my $cb = sub ($pubsub, $message) {
	$c->app->log->info($c->session('roomid'));
	$c->send($message)
    };


    $c->app->log->info($c->session('roomid'));
    my $channel = 'mojochat::' . $c->session('roomid');
    $c->pg->pubsub->listen($channel => $cb);
    
    # Remove callback from PG listeners on close
    $c->on(finish => sub ($c, @) {
	       $c->app->log->info($c->session('roomid'));

	       my $channel = 'mojochat::' . $c->session('roomid');

	       $c->pg->pubsub->unlisten($channel => $cb);
	   });
};

app->start;
__DATA__

@@ chat.html.ep
<script src="https://cdnjs.cloudflare.com/ajax/libs/vue/2.0.5/vue.js"></script>
<!-- reveal begin template -->
<div id="chat">
  Username: <input v-model="username"><br>
  Send: <chat-entry @message="send"></chat-entry><br>
  <div id="log">
    <chat-msg v-for="m in messages" :username="m.username" :message="m.message"></chat-msg>
  </div>
</div>
<!-- reveal end template -->
<script>
// reveal begin entry
Vue.component('chat-entry', {
  template: '<input @keydown.enter="message" v-model="current">',
  data: function() { return { current: '' } },
  methods: {
    message: function() {
      this.$emit('message', this.current);
      this.current = '';
    },
  },
});
// reveal end entry
// reveal begin message
Vue.component('chat-msg', {
  template: '<p>{{username}}: {{message}}</p>',
  props: {
    username: { type: String, required: true },
    message:  { type: String, default: '' },
  },
});
// reveal end message
// reveal begin app
var vm = new Vue({
  el: '#chat',
  data: { messages: [], username: '', ws: null },
  methods: {
    connect: function() {
      var self = this;
      self.ws = new WebSocket('<%= url_for('channel')->to_abs %>');
      self.ws.onmessage = function (e) {
	  console.log(e);
	  var d = JSON.parse(e.data);
	  if (d.username) {
	      self.messages.push(d)
	  } else if (d.path) {
	      console.log(d.path);
	  }
      };
    },
    send: function(message) {
      var data = {username: this.username, message: message};
      this.ws.send(JSON.stringify(data));
    },
  },
  created: function() { this.connect() },
});
// reveal end app
</script>
@@ create_room.html.ep
<script
  src="https://code.jquery.com/jquery-3.4.1.min.js"
  integrity="sha256-CSXorXvZcTkaix6Yvo6HppcZGetbYMGWSFlBw8HfCJo="
  crossorigin="anonymous"></script>
<a id="createRoom" href="#">create a new room</a>
    <script>
    function create_uuidv4() {
	return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
	    var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
	    return v.toString(16);
	});
    }
    $(function(){
	$('#createRoom').on('click', e => {
	    var uuid4 = create_uuidv4();
	    console.log(uuid4);
	    window.location = '<%= url_for('room/')->to_abs %>' + uuid4;
	})
    })
</script>
@@ canvas.html.ep
<script src="https://cdnjs.cloudflare.com/ajax/libs/paper.js/0.12.2/paper-full.min.js"></script>
    <script type="text/paperscript" canvas="canvas">

console.log(project)

    var messages = [];
    var ws = new WebSocket('<%= url_for('channel')->to_abs %>');
ws.onmessage = function (e) {
    console.log('e', e);
    var d = JSON.parse(e.data)

    console.log('d', d);

    var path = Item.importJSON(e.data);
    console.log('path', path);
    path.addTo(project);
};


  var path;
  
  var textItem = new PointText({
  content: 'Click and drag to draw a line.',
  point: new Point(20, 30),
            fillColor: 'black',
  });
  
  function onMouseDown(event) {
  // If we produced a path before, deselect it:
  if (path) {
      path.selected = false;
  }
      
      // Create a new path and set its stroke color to black:
      path = new Path({
          segments: [event.point],
          strokeColor: 'black',
          // Select the path, so we can see its segment points:
          fullySelected: true
      });
      
  }

// While the user drags the mouse, points are added to the path
// at the position of the mouse:
function onMouseDrag(event) {
    path.add(event.point);
    
    // Update the content of the text item to show how many
    // segments it has:
    //textItem.content = 'Segment count: ' + path.segments.length;
    
    
}

// When the mouse is released, we simplify the path:
function onMouseUp(event) {
    var segmentCount = path.segments.length;
    
    // When the mouse is released, simplify it:
    path.simplify(10);
    
    // Select the path, so we can see its segments:
    path.fullySelected = true;
    
    var newSegmentCount = path.segments.length;
    var difference = segmentCount - newSegmentCount;
            var percentage = 100 - Math.round(newSegmentCount / segmentCount * 100);
    //textItem.content = difference + ' of the ' + segmentCount + ' segments were removed. Saving ' + percentage + '%';
    
    sendstuff(path);
}


function sendstuff(path)
{
    console.log("sending stringified", JSON.stringify(path.toJSON()))
    ws.send(JSON.stringify(path.toJSON()))
}

</script>
</head>
<body>
    <canvas style="background-color:#dddddd" id="canvas" resize></canvas>
</body>
</html>

    
