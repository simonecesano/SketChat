function createUUIDv4() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
	var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
	return v.toString(16);
    });
}

class SketChat {
    constructor(channelUrl, paper, options) {
	var sketChat = this;
	var signature = Cookies.get('signature');

	this.processMessage = function(message, replaceAll) {
	    var d = JSON.parse(message);
	    console.log(d);
	    if ((signature !== d.signature) || replaceAll) {
		if (d.paperCommand) {
		    try {
			console.log('paper.' + d.paperCommand);
			eval('paper.' + d.paperCommand);
			return true;
		    } catch(e) {
			console.log('command ' + d.paperCommand + ' failed');
			console.log(e);
			return false
		    }
		} else if (d.paperItem) {
		    var itemData = JSON.stringify(d.paperItem)
		    try {
			var path = Item.importJSON(itemData);
			path.addTo(paper.project);
			return path;
		    } catch (e) {
			console.log(e);
			return false
		    }
		} else if (d.alive) {
		} else {
		    try {
			var path = Item.importJSON(message);
			path.addTo(paper.project);
			return path;
		    } catch (e) {
			console.log(e);
			return false
		    }
		}
	    }
	}

	var ws = new WebSocket(channelUrl);
	ws.onmessage = function (e) {
	    sketChat.processMessage(e.data) 
	};
	this.socket = ws;
	
	window.setInterval(function(){
	    try {
		ws.send(JSON.stringify({ alive: signature, time: (new Date()).getTime() }))
	    } catch(e) {
		console.log(e);
	    }
	}, 15000);
    }
};


class Brush {
    constructor(project, socket, options) {
	this.project = project;
	this.socket = socket;
	this.options = options;
	this.path = new Path();
    }

    doDown(point) { }

    doDrag(point){ }

    doUp(point) { }
    
    get onMouseDown() {
	return function(event){
	    console.log(event);
	}
    }

    get onMouseDrag() {
	return function(event){
	    console.log(event);
	}
    }

    get onMouseUp(){
	return function(event){
	    console.log(event);
	}
    }
}

class InkBrush extends Brush {
    constructor(project, socket, options) {
	super(project, socket, options)
	var app = this;
	Pressure.set(app.project.view.element, {
	    change: function(f, event){ app.force = f }
	});
    }

    
    get onMouseDown() {
	var app = this;
	
	return function(event){
	    if (app.path) { app.path.selected = false }

	    app.path = new Path()
	    app.path.strokeColor = undefined;
	    app.path.fillColor   = '#222222aa';
	    app.path.add(event.point);
	    app.path.name = createUUIDv4();
	    app.path.addTo(app.project);
	}
    }

    get onMouseDrag() {
	var app = this;

	return function(event){
	    // -----------------------------------------------
	    // force should be [a basis] + [a factor] * force
	    // -----------------------------------------------

	    var step = event.delta.normalize().multiply(app.force * 10);
	    step.angle += 90;

	    // -----------------------------------------------
	    // NB: using + and - directly doesn't
	    // seem to work in plain Javascript
	    // -----------------------------------------------

	    var top =    event.middlePoint.add(step);
	    var bottom = event.middlePoint.subtract(step);
	    
	    app.path.add(top.round());
	    app.path.insert(0, bottom.round());

	    app.path.smooth();
	}
    }

    get onMouseUp(){
	var app = this;
	
	return function(event){
	    app.path.add(event.point);
	    app.path.closed = true;
	    app.path.smooth();
	    app.socket.send(JSON.stringify({ paperItem: app.path.toJSON() }))
	}
    }
}

class Sharpie extends Brush {

    get onMouseDown() {
	var app = this;
	
	return function(event){
	    if (app.path) { app.path.selected = false }

	    app.path = new Path()
	    app.path.strokeColor = 'black';
	    app.path.strokeWidth = 10;
	    app.path.add(event.point);
	    app.path.name = createUUIDv4();
	    app.path.addTo(app.project);	
	};
    }
    
    get onMouseDrag() {
	var app = this;
	return function(event){
	    app.path.add(event.point);
	}
    };
	
    get onMouseUp() {
	var app = this;
	return function(event){
	    app.path.simplify();
	    var outerPath = OffsetUtils.offsetPath(app.path, 4);

	    
	    var innerPath = OffsetUtils.offsetPath(app.path, -4);
	    innerPath.strokeColor = 'black';
	    outerPath.reverse();

	    innerPath.join(outerPath);
	    innerPath.closePath()
	    innerPath.fillColor = "black";
	    innerPath.insertBelow(app.path);

	    app.path.remove();
	    app.path = innerPath;
	    app.path.name = createUUIDv4();
	    app.socket.send(JSON.stringify({ paperItem: app.path.toJSON() }))
	}
    };
}

class Eraser extends Brush {
    constructor(project, socket, options) {
	super(project, socket, options)

	this.eraseCircle = undefined;
	this.changedItems = {};
    }

    get onMouseDown() {
	var app = this;
	return function(event) {
	    app.eraseCircle = new Path.Circle(event.point, 12)
	    app.eraseCircle.fillColor = "#ffffff88";
	    app.eraseCircle.name = "eraser";
	    app.changedItems = {};
	}
    }
    
    // ---------------------------------------------------------
    // 1. keep track of changed (added, removed) items
    // 2. for every added item, send a creation command
    // 3. for every deleted command, send a delete command
    // ---------------------------------------------------------
    // How would it work if it sent the path of the eraser?
    // ---------------------------------------------------------
    
    get onMouseDrag() {
	var app = this;
	return function(event) {
	    app.eraseCircle.position = event.point
	    var intersects = app.project.getItems( { recursive: true, overlapping: app.eraseCircle.bounds })
		.filter(item => { return item.id !== app.eraseCircle.id && item.className !== "Layer" })
	    ;
	    
	    intersects.forEach(i => {
		if (i.intersects(app.eraseCircle) || i.isInside(app.eraseCircle)) {
		    var uuid = createUUIDv4()
		    
		    var erased = i.subtract(app.eraseCircle, { insert: true })
		    erased.name = uuid;
		    
		    app.changedItems[uuid] = 'added';
		    app.changedItems[i.name] = 'removed';
		    i.remove();
		} else if (false) {
		    
		}
	    })
	}
    }
	
    get onMouseUp() {
	var app = this;
	return function(event) {
	    app.project.getItems({ recursive: true }).forEach(i => {
		var bounds = i.bounds
		if (bounds.width * bounds.height < 1) {
		    // changedItems[i.name] = 'removed'
		    i.remove()
		}
	    })
	    app.eraseCircle.remove()
	    if (true) {
		console.log(app.changedItems);
		for (var uuid in app.changedItems) {
		    if (app.project.getItems({ name: uuid }).length) {
			app.socket.send(JSON.stringify({ paperItem: project.getItem({ name: uuid}).toJSON() }));
		    } else {
			app.socket.send(JSON.stringify({ paperCommand: 'project.getItem({ name: "' + uuid + '"}).remove()' }))
		    }
		}
		app.changedItems = {};
	    }
	}
    }
};
