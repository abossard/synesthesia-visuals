function setup() {
	c = createCanvas(windowWidth, windowHeight);
	background(60);

	ix = 0
	RW = min(windowWidth,windowHeight)
	RH = RW
	
	colorMode(HSB,255)
	placename = "Netherlands"
	switch (placename)
	{
		case "Greece": place = 1 ; break;
		case "Florida": place = 2 ; break;
		case "Morocco": place = 3 ; break;
		case "Norway": place = 4 ; break;
		case "Netherlands": place = 5 ; break;
	}
	
	termap = [4,4,4,
					  2,5,3,
					  2,1,3]
	terw = 3
	terh = 3
	treebiomecol = [color(80,255,100),color(65,200,85),color(110,120,160),color(110,120,100),color(80,180,130)]
	wallcol = [color(0,0,220),color(25,100,200),color(40,50,230),color(30,130,170),color(40,150,200)]
	roofcol = [color(0,150,250),color(10,150,250),color(20,150,250), //Greece
						color(10,100,180),color(10,100,150),color(10,100,120), //Florida
						color(10,50,145),color(10,50,130),color(10,50,115),		 //Morocco
						color(10,50,135),color(10,50,120),color(10,50,105),	   //Norway
						color(5,200,150),color(15,200,150),color(25,200,150)]  //Netherlands
	//noiseSeed(11)
}


function keyPressed() {

if (keyCode == 82) {ix = 0 ; noiseSeed(random(10000)) ; background(100)}
if (keyCode == 80) {saveCanvas(place+floor(random(1000))+".jpg", 'jpg')}
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
			//ix = rx-ry ; iy = rx+ry
			nx = ix-12+24*noise(ix/15+1000,iy/15+1000)
			ny = iy-12+24*noise(ix/15+1000,iy/15+2000)
			m = noise(nx/200,ny/200)+0.05
			v = noise(nx/30,ny/30+1000)
			a = noise(nx/2000,ny/2000+5000)
			l = noise(nx/300+1000,ny/300)-0.5+0.2*(a-0.5)
			t = noise(nx/2000,ny/2000+3000)
			
			humid = max(0,min(2,1+6*(a-0.5))) ; if (abs((humid%1)-0.5) < 0.125) {humid += 3*(humid-floor(humid)-0.5)} else {humid = round(humid)}
			hot = max(0,min(2,1+6*(t-0.5))) ; if (abs((hot % 1)-0.5) < 0.125) {hot += 3*(hot-floor(hot)-0.5)} else {hot = round(hot)}
			
			place = termap[round(humid)+terw*round(hot)]
			flhumid = termap[floor(humid)+terw*round(hot)]
			clhumid = termap[ceil(humid)+terw*round(hot)]
			flhot = termap[round(humid)+terw*floor(hot)]
			clhot = termap[round(humid)+terw*ceil(hot)]
			
			
			treeheightdeterrent = 1.5 ; cityheightdeterrent = 0.5
			snowcol = color(180,10,230+abs(20*sin(v*20)))
			
			
			if (flhumid == clhumid && flhot == clhot && flhot == flhumid)
			{
				//if (flhot == clhot)
				//{
				h = get_height(flhot,1)
				col = get_col(flhot,h+0.01*sin(h*PI*32),m)
				}
				/*else
				{
				h = lerp(get_height(flhot,1-(hot % 1)),get_height(clhot,hot % 1),hot % 1)
				col1 = get_col(flhot,h+0.01*sin(h*PI*32),m)
				col2 = get_col(clhot,h+0.01*sin(h*PI*32),m)
				colorMode(RGB,255) ; col = lerpColor(col1,col2,hot % 1) ; colorMode(HSB,255)
				}
			}
			else
			{
				if (flhot == clhot)
				{
				h = lerp(get_height(flhumid,1-(humid % 1)),get_height(clhumid,humid % 1),humid % 1)
				col1 = get_col(flhumid,h+0.01*sin(h*PI*32),m)
				col2 = get_col(clhumid,h+0.01*sin(h*PI*32),m)
				colorMode(RGB,255) ; col = lerpColor(col1,col2,humid % 1) ; colorMode(HSB,255)
				}*/
				else
				{
				flfl = termap[floor(humid)+terw*floor(hot)]
				clfl = termap[ceil(humid)+terw*floor(hot)]
				flcl = termap[floor(humid)+terw*ceil(hot)]
				clcl = termap[ceil(humid)+terw*ceil(hot)]
				var nhu = humid % 1
				var nho = hot % 1
				h = lerp(lerp(get_height(flfl,(1-nhu)*(1-nho)),get_height(clfl,(nhu)*(1-nho)),nhu),
						     lerp(get_height(flcl,(1-nhu)*(  nho)),get_height(clcl,(nhu)*(  nho)),nhu),nho)
				
				var nh = h+0.01*sin(h*PI*32)
				col1 = get_col(flfl,nh,m) ; col2 = get_col(clfl,nh,m)
				col3 = get_col(flcl,nh,m) ; col4 = get_col(clcl,nh,m)
				colorMode(RGB,255) ; col = lerpColor(lerpColor(col1,col2,humid % 1),lerpColor(col3,col4,humid % 1),hot % 1) ; colorMode(HSB,255)
				}
			//}
			
			forest = (-1+2*noise(nx/100+2000,ny/100+h))/10
			colorMode(RGB,255) ; stroke(lerpColor(col,snowcol,min(0.9,-t*10))) ; colorMode(HSB,255)
			
			nx = ix-75+150*noise(ix/250+1000,iy/250+1000) //new, lower frequency distortion
			ny = iy-75+150*noise(ix/250+1000,iy/250+2000)
			houseid = floor(nx/8)*829+floor(ny/8)*1091
			housenoise = noise(floor(nx/8)/12,floor(ny/8)/12+100)
			
			if (place == 5 && forest < 0.02 && abs(housenoise-0.5) < 0.1 && h > 0.01 && m < 0.65 && h < 0.2 && nx % 48 > 2 && ny % 48 > 2)
			{
				var wheatcol = color(9*(5*floor(nx/48)+3*floor(ny/48)) % 95,255,128+random(128))
				colorMode(RGB,255)
				stroke(lerpColor(col,wheatcol,0.2))
				colorMode(HSB,255)
				h+=random(0.01)
			}
			else if (nx % 8 < 6 && ny % 8 < 6 && h > 0.01 && m < 0.8 && housenoise > h*cityheightdeterrent+0.5+0.4*noise(houseid))
			{
				stroke((nx % 8 > 4.5 || ny % 8 > 4.5) ? wallcol[place-1] : roofcol[(place-1)*3+(houseid%3)]) ; h += 0.02
			}
			else if ((forest+0.05*sq(random()))*(sq(random())*4) > h*treeheightdeterrent && h > 0.01) //it's a tree!
			{
				stroke(lerpColor(col,t < 0 ? color(110,1,230) : treebiomecol[place-1],random(1))) ; h += random(0.05)
			}
			
			if (h*80 > 1)
			line(windowWidth/2+ix-iy,ix/2+iy/2-80*h,windowWidth/2+ix-iy,ix/2+iy/2)
			else
			point(windowWidth/2+ix-iy,ix/2+iy/2)
		}
		ix ++
	}
}

function get_height(p,i) {
switch (p)
{
	case 1: var h = 2.5*sq(sq(m))*abs(v-0.5)+2.65*(l) ; break;
	case 2: h = sq(m-0.5)/2+l/3+12.5*sq(sq(m-0.1))*abs(v-0.5) ; h += 0.75*max(0,0.1-abs(h))*(abs(sin(v*2*PI))-0.5) ; break;
	case 3: h = m/5+v/5+l/2 ; h += max(0,min(1,h*10))*sin(ix/150+iy/20+m*160)/10*(sq(l+0.55)+v/10) ; treeheightdeterrent += 1.5*i ; cityheightdeterrent += 1.5*i ; break;
	case 4: h = m/5+v/2+l/1.8-0.1 ; h += abs(v-0.5)*max(0,h)*m*4 ; cityheightdeterrent = 2 ; t += i*(-h-0.55+noise(nx/15+2000,ny/15)/5) ; break;
	case 5: h = sq(m-0.5)/2+l/4+3.5*sq(sq(m-0.1))*abs(v-0.5) ; h += 0.06-0.1*sq(sq(sq(0.05+sin(ix/150+l*3+t*5+m*4)))) ; break;
}
return(h)
}

function get_colt(p,h,m) {return(color(40*p,150,255))}

function get_col(p,h,m) {
switch(p)
	{
case 5: //NETHERLANDS
	if (h < 0)	//water
		return(color(150-30*h-max(200*h,-15),110-30*h+max(200*h,-30)-100*h-100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4)),240+h*65))
	else				//land
		return(color(70-min(20,h*100)-h*55,200-h*600,150+min(h*500,30)+100*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))

case 4: //NORWAY
	if (h < 0)	//water
		return(color(150-30*h-max(200*h,-15),130-30*h+max(200*h,-30)-100*h-100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4)),250))
	else				//land
		return(color(50-min(25,h*200)-h*50,120-h*300,150+min(h*500,30)-100*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
break;

case 3: //MOROCCO
	if (h < 0)
		return(color(120-30*h-max(350*h,-25),150-100*h,200-max(350*h,-25)+100*h+100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4))))
	else
		return(color(80-min(40,h*500)-h*50,100-h*150,150+min(h*500,30)+150*h-5*(ix % 4 ? 0 : 1)+5*(iy % 4 ? 0 : 1)))
break;
		
case 2: //FLORIDA
	if (h < 0)
		return(color(160-30*h+10*max(0,1+h*15),150-100*h-150*max(0,-2.25+3.5*noise((ix-iy)/40+1500,(ix+iy)/8)),255+h*500-100*max(0,1+h*15)))
	else
		return(color(120-m*20-min(60,h*300),150-h*200,100+min(h*500,30)+150*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
break;

case 1: //GREECE
	if (h < 0)
		return(color(120-30*h-max(350*h,-50),150-100*h,200-max(350*h,-50)+100*h+100*max(0,-2+3.5*noise((ix-iy)/40,(ix+iy)/4))))
	else if (h > 0.01)
		return(color(100-m*50-min(20,h*100),200-h*300,150+200*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)))
	else
		return(lerpColor(color(40,100,240-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)),color(100-m*50-min(20,h*100),200-h*300,150+200*h-4*(ix % 4 ? 0 : 1)+4*(iy % 4 ? 0 : 1)),h/0.01))
	break;
}}