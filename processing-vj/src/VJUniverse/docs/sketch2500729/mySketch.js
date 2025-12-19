function setup() {
	createCanvas(900,900);
	render()
}

function draw() {

}

function mousePressed(){
	render()
}

function keyPressed(){
	save("genuary-05.jpg")
}

function render(){
	let variance = 0.03
	noiseSeed(random(10000))
	background(255);
	let l = 5;
	for(let i = 0; i < 350; i++){
		for(let j = 0; j < 350; j++){
			isometricRect(width/2.0+i*l*cos(PI+PI/6.0)+j*l*cos(PI/6.0),-200+i*l*sin(PI/6.0)+j*l*sin(PI/6.0),l,int(map(noise(i*variance,j*variance),0,1,1,50))*5)
		}
	}
}

function isometricRect(x,y,w,h){
	push()
	translate(x,y-h)
	//TOP
	let hue = constrain(map(h,0,50*5,360,0),100,260)
	for(let i = 0; i < 1; i++){
		noStroke()
		colorMode(HSB)
		fill(hue,100,90)
		beginShape()
		vertex(0,0)
		vertex(w*cos(-PI/6.0),w*sin(-PI/6.0))
		vertex(0,2*w*sin(-PI/6.0))
		vertex(w*cos(PI+PI/6.0),w*sin(PI+PI/6.0))
		endShape(CLOSE)
		//RIGHT
		fill(hue,100,70)
		beginShape()
		vertex(0,0)
		vertex(w*cos(-PI/6.0),w*sin(-PI/6.0))
		vertex(w*cos(-PI/6.0),w*sin(-PI/6.0)+h)
		vertex(0,h)
		endShape(CLOSE)
		//LEFT
		fill(hue,100,50)
		beginShape()
		vertex(0,0)
		vertex(w*cos(PI+PI/6.0),w*sin(PI+PI/6.0))
		vertex(w*cos(PI+PI/6.0),w*sin(PI+PI/6.0)+h)
		vertex(0,h)
		endShape(CLOSE)
	}
	pop()
}