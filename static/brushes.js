function createUUIDv4() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
	var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
	return v.toString(16);
    });
}


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
	    // sendstuff(path);
	    app.socket.send(JSON.stringify({ paperItem: app.path.toJSON() }))
	}
    }
}

class Sharpie extends InkBrush {
    get onMouseDrag() {
	var app = this;

	return function(event){
	    // -----------------------------------------------
	    // force should be [a basis] + [a factor] * force
	    // -----------------------------------------------

	    var step = event.delta.normalize().multiply(8);
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
