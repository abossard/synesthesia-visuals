function setup() {
	c = createCanvas(windowWidth, windowHeight);
	background(100);

	ix = 0
	RW = min(windowWidth,windowHeight)
	RH = RW
	
	colorMode(HSB,255)
	place = "Norway"
	//noiseSeed(11)
}


function keyPressed() {

if (keyCode == 82) {ix = 0 ; noiseSeed(random(10000)) ; background(100)}
if (keyCode == 80) {saveCanvas(place+floor(random(1000))+".png", 'png')}
}

function mouseClicked() {
if (keyCode == 82) {ix = 0 ; noiseSeed(random(10000)) ; background(100)}
}


function draw() {
	
	noSmooth()
	
	if (ix < RW)
	for(var nc=0;nc<5;nc++)
	{
		for(iy=0;iy<RH;iy++)
		{
			nx = ix-12+24*noise(ix/15+1000,iy/15+1000)
			ny = iy-12+24*noise(ix/15+1000,iy/15+2000)
			m = noise(nx/200,ny/200)+0.05
			v = noise(nx/30,ny/30+1000)
			l = noise(nx/300+1000,ny/300)-.5
			t = noise(nx/400,ny/400+1000)*.75+0.1
			
			treeheightdeterrent = 1.5 ; cityheightdeterrent = 0.5
			if (place == "Greece") h = 2.5*sq(sq(m))*abs(v-.5)+0.65*(l)
			if (place == "Florida") {h = sq(m-.5)/2+l/3+2.5*sq(sq(m-.1))*abs(v-.5) ; h += 0.75*max(0,.1-abs(h))*(abs(sin(v*2*PI))-.5)}
			if (place == "Morocco") {h = m/5+v/10+l/2 ; h += max(0,min(1,h*10))*sin(ix/15+iy/10+m*80)/10*(sq(l+.55)+v/10) ; treeheightdeterrent = 3 ; cityheightdeterrent = 2}
			if (place == "Norway") {h = m/5+v/10+l/1.8-.1 ; h += abs(v-.5)*max(0,h)*m*8 ; cityheightdeterrent = 2 ; t += -h-.55+noise(nx/15+2000,ny/15)/5}
			
			forest = (-1+2*noise(nx/100+2000,ny/100+h))/10
			
			col = get_col_Norway(h+0.01*sin(h*PI*32),m)
			snowcol = color(180,10,230+abs(20*sin(v*20)))
			colorMode(RGB,255)
			stroke(lerpColor(col,snowcol,min(.9,-t*10)))
			colorMode(HSB,255)
			
			nx = ix-75+150*noise(ix/250+1000,iy/250+1000) //new, lower frequency distortion
			ny = iy-75+150*noise(ix/250+1000,iy/250+2000)
			houseid = floor(nx/8)*829+floor(ny/8)*1091
			
			if (nx % 8 < 6 && ny % 8 < 6 && h > 0.01 && m < .8 && noise(floor(nx/8)/12,floor(ny/8)/12+100) > h*cityheightdeterrent+0.5+0.4*noise(houseid))
			{
				stroke((nx % 8 > 4.5 || ny % 8 > 4.5) ? color(30,130,170) : color(10,50,130-10*(houseid % 3))) ; h += 0.02
			}			
			else if ((forest+0.05*sq(random()))*(sq(random())*4) > h*treeheightdeterrent && h > 0.01) //it's a tree!
			{
				stroke(lerpColor(col,t < 0 ? color(110,1,230) : color(110,120,100),random(1))) ; h += random(0.05)
			}
			
			if (h*80 > 1)
			line(windowWidth/2+ix-iy,ix/2+iy/2-80*h,windowWidth/2+ix-iy,ix/2+iy/2)
			else
			point(windowWidth/2+ix-iy,ix/2+iy/2)
		}
		ix ++
	}
}


function get_col_Norway(h,m) {
	if (h < 0)	//water
		return(color(150-30*h-max(200*h,-15),130-30*h+max(200*h,-30)-100*h-100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4)),250))
	else				//land
		return(color(50-min(25,h*200)-h*50,120-h*300,150+min(h*500,30)-100*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
}


function get_col_Morocco(h,m) {
	if (h < 0)
		return(color(120-30*h-max(350*h,-50),150-100*h,200-max(350*h,-50)+100*h+100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4))))
	else
		return(color(80-min(40,h*500)-h*50,100-h*150,150+min(h*500,30)+150*h-5*(ix % 4 ? 0 : 1)+5*(iy % 4 ? 0 : 1)))
}


function get_col_Florida(h,m) {

	if (h < 0)
		return(color(160-30*h+10*max(0,1+h*15),150-100*h-150*max(0,-2.25+3.5*noise((ix-iy)/40+1500,(ix+iy)/8)),255+h*500-100*max(0,1+h*15)))
	else
		return(color(120-m*20-min(60,h*300),150-h*200,100+min(h*500,30)+150*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
}

function get_col_Greece(h,m) {

	if (h < 0)
		return(color(120-30*h-max(350*h,-50),150-100*h,200-max(350*h,-50)+100*h+100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4))))
	else if (h > 0.01)
		return(color(100-m*50-min(20,h*100),200-h*300,150+200*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
	else
		return(lerpColor(color(40,100,240-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)),color(100-m*50-min(20,h*100),200-h*300,150+200*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)),h/0.01))
}