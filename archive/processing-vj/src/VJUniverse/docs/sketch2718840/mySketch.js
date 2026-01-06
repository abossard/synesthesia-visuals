//mouse X and mouseY animations////////////////
//the eyes follow
//fangs grow
//lightning fades in
//spider and string move

//custom variable animations//////////////////
//sky changes colors
//clouds move in
//plant changes colors
//jack o lantern face fades in
//ghost fades in
//candles fade in

//other/////////////////
//candles "flicker" with random 
//lightning only appears when the sky is dark
let sky = 1
let light = 0
let cloud1 = 285
let cloud2 = 90
let cloud3 = 284
let decay = 1
let string = 265
let body = 268
let eye = 269
let leg11and21 = 307
let leg12 = 300
let leg22 = 304
let leg31 = 310
let leg32 = 309
let leg41 = 312
let leg42 = 317
let leg51and61 = 307
let leg52 = 302
let leg62 = 306
let leg71andleg72 = 310
let leg81 = 312
let leg82 = 317
let ghost = 0
function setup() {
	createCanvas(500, 500);
	background(80); 
}
function draw() {
	//SKY/////////////////////
	fill(134, 185, 177)
	quad(152, 114, 222, 75, 222, 242, 152, 275)
	//darker
	fill (25,69,79,sky);
	quad(152, 114, 222, 75, 222, 242, 152, 275)
	sky = sky + 1;
	stroke(0)
	//LIGHTNING/////////////////
	if (sky>255){
		let y5 = map(mouseY, 100, 400, 0, 255, true);
		stroke(255,y5);
		line(181,145,168,178);
		line(168,178,179,200);
		line(179,200,173,230);
		line(173,230,183,253);
	}
	stroke(0)
	//CLOUDS///////////////////////
	//bottom
	fill(67,124,135)
	ellipse(cloud3,144,70,30)
	cloud3 = cloud3 - 0.3
	cloud3 = constrain (cloud3,207,400)
	//middle
	fill(8,56,69)
	ellipse(cloud2,135,90,30)
	cloud2 = cloud2 + 0.2
	cloud2 = constrain (cloud2,90,135)
	//top
	fill(1,33,45)
	ellipse(cloud1,108,100,60)
	cloud1 = cloud1 - 0.35
	cloud1 = constrain (cloud1,190,400)
	//SIDES OF CUBE//////////////
	//side left
	fill(38, 42, 32)
	quad(40, 124, 50, 130, 50, 370, 40, 376)
	//top left
	fill(63, 71, 50)
	quad(250, 9, 250, 20, 50, 130, 40, 124)
	//top right
	fill(63, 71, 50)
	quad(250, 20, 250, 9, 460, 124, 450, 130)
	//side right
	fill(16, 18, 14)
	quad(450, 130, 460, 124, 460, 376, 450, 370)
	//bottom left
	fill(38, 42, 32)
	quad(40, 376, 50, 370, 250, 480, 250, 491)
	//bottom right
	fill(16, 18, 14)
	quad(450, 370, 460, 376, 250, 491, 250, 480)
	//WALLS//////////////////////
	//left wall
	fill(25, 28, 22)
	//left left
	beginShape();
	vertex(152,74)
	vertex(50,130)
	vertex(50,370)
	vertex(152,322)
	endShape();
	//right left
	beginShape();
	vertex(213,40.5)
	vertex(250,20)
	vertex(250,276)
	vertex(213,294)
	endShape();
	//top left
	noStroke()
	beginShape();
	vertex(152,74)
	vertex(213,40.5)
	vertex(213,80)
	vertex(152,114)
	endShape();
	//bottom left
	beginShape();
	vertex(152,322)
	vertex(221,289)
	vertex(221,242)
	vertex(152, 275)
	endShape();
	//window outline
	stroke(1)
	line(152,114,222,75)
	line(222,75,222,242)
	line(222,242,152,275)
	line(152,275,152,114)
	//wall top and bottom
	line(50,130,250,20)
	line(50,370,250,276)
	//right wall
	fill(38, 42, 32)
	quad(250, 20, 450, 130, 450, 370, 250, 276)
	//floor
	fill(67, 40, 26)
	quad(50, 370, 250, 276, 450, 370, 250, 480)
	//floor panels
	line(73, 383, 271, 287)
	line(98, 396, 293, 297)
	line(122, 410, 316, 307)
	line(147, 423, 340, 319)
	line(171, 437, 366, 331)
	line(198, 452, 393, 344)
	line(226, 466, 422, 357)
	//WINDOW/////////////////////
	//window sill
	fill(63, 71, 50)
	quad(152, 265.5, 213, 237, 222, 242, 152, 275)
	//side wall
	quad(213, 80, 222, 75, 222, 242, 213, 237)
	//CURTAIN////////////////////
	//curtian rod
	fill(207, 214, 214)
	quad(127, 110, 239, 52, 240, 57, 128, 116)
	ellipse(129, 112, 12, 12)
	ellipse(240, 55, 12, 12)
	//curtain
	fill(92, 10, 36, 100)
	beginShape();
	vertex(202, 68)
	vertex(226, 55)
	vertex(238, 250)
	curveVertex(223, 263)
	vertex(206, 265)
	endShape(CLOSE);
	//FANGS PAINTING////////////////////////
	//right 
	fill(0)
	quad(73,180,78,183,78,273,73,270)
	//top
	quad(128,151,134,154,78,183,73,180)
	//frame
	fill(20)
	quad(78,183,134,154,134,246,78,273)
	//inside
	fill(92,10,36)
	quad(84,188,128,165,128,241,84,263)
	//shadow 
	fill(5)
	quad(125,167,128,165.5,128,241,125,239)
	quad(128,241,125,239,84,259,84,263)
	//teeth
	fill(207, 214, 214)
	quad(94,211,116,200,116,209,94,220)
	line(105,206,105,214)//middle
	line(99,209,99,217)//left
	line(111,203,111,211)//right
	//fang left top
	beginShape();
	vertex(88,223)
	vertex(88,214)
	vertex(94,211)
	vertex(94,220)
	endShape();
	//right top
	beginShape();
	vertex(116,209)
	vertex(116,200)
	vertex(121,197)
	vertex(121,207)
	endShape();
	//left bottom
	let y1 = map(mouseY,100,400,224,240,true)
	beginShape();
	vertex(88,222.5)
	vertex(90,y1)
	vertex(94,219.5)
	endShape();
	//right bottom
	let y2 = map(mouseY,100,400,209,227,true)
	beginShape();
	vertex(116,208.5)
	vertex(120,y2)
	vertex(121,206.5)
	endShape();
	//PLANT/////////////////////	
	//plant pot
	fill(246, 229, 195)
	quad(146, 275, 173, 275, 173, 331, 146, 331)
	ellipse(159.5, 275, 27.5, 7)
	arc(159.5, 330.3, 27, 9, radians(0), radians(180), OPEN);
	//dirt
	fill(67, 40, 26)
	ellipse(159.5, 276.5, 20, 3)
	//plant stem
	fill(105, 224, 133)
	beginShape();
	vertex(154.5, 276)
	vertex(158.5, 254)
	vertex(146.5, 244)
	vertex(141.5, 224)
	vertex(150.5, 244)
	vertex(162.5, 253)
	vertex(158.5, 276)
	endShape(CLOSE)
	fill(100,decay)
	beginShape();
	vertex(154.5, 276)
	vertex(158.5, 254)
	vertex(146.5, 244)
	vertex(141.5, 224)
	vertex(150.5, 244)
	vertex(162.5, 253)
	vertex(158.5, 276)
	endShape(CLOSE)
	decay = decay + 0.3;
	//lil leaf left
	fill(105, 224, 133)
	beginShape();
	vertex(144.5, 238)
	vertex(138.5, 236)
	vertex(136.5, 233)
	vertex(131.5, 229)
	vertex(139.5, 230)
	endShape(CLOSE);
	fill(100,decay)
	beginShape();
	vertex(144.5, 238)
	vertex(138.5, 236)
	vertex(136.5, 233)
	vertex(131.5, 229)
	vertex(139.5, 230)
	endShape(CLOSE);
	decay = decay + 0.3
	//lil leaf right
	fill(105, 224, 133)
	beginShape();
	vertex(155.5, 247)
	vertex(158.5, 241)
	vertex(164.5, 239)
	vertex(162.5, 241)
	vertex(159.5, 248)
	endShape(CLOSE);
	fill(100,decay)
	beginShape();
	vertex(155.5, 247)
	vertex(158.5, 241)
	vertex(164.5, 239)
	vertex(162.5, 241)
	vertex(159.5, 248)
	endShape(CLOSE);
	decay = decay + 0.3
	//PUMPKIN///////////////////////////////
	fill(207, 37, 1)
	ellipse(128.5, 328, 65, 50)
	ellipse(128.5,328,45,50)
	ellipse(128.5,328,26,50)
	//left eye
	stroke(0,ghost)
	fill(240,226,33,ghost)
	beginShape();
	vertex(108.5,314)
	curveVertex(122.5,326)
	vertex(110.5,324)
	endShape(CLOSE)
	//right eye
	beginShape();
	vertex(147.5,314)
	curveVertex(134.5,326)
	vertex(146.5,324)
	endShape(CLOSE)
	//nose
	beginShape();
	vertex(124.5,332)
	vertex(128.5,326)
	vertex(132.5,332)
	vertex(128.5,330)
	endShape(CLOSE)
	//mouth
	beginShape();
	vertex(102.5,331)
	vertex(112.5,336)
	vertex(117.5,334)
	vertex(120.5,339)
	vertex(123.5,336)
	vertex(128.5,339)
	vertex(132.5,336)
	vertex(135.5,339)
	vertex(138.5,335)
	vertex(143.5,336)
	vertex(154.5,331)
	vertex(142.5,342)
	vertex(139.5,340)
	vertex(136.5,346)
	vertex(131.5,341)
	vertex(128.5,346)
	vertex(124.5,341)
	vertex(120.5,346)
	vertex(117.5,339)
	vertex(113.5,342)
	endShape(CLOSE);
	stroke(0)
	//pumpkin stem
	fill(60,77,60)
	beginShape();
	vertex(121.5,311)
	vertex(123.5,300)
	vertex(130.5,300)
	vertex(133.5,311)
	endShape(CLOSE);
	line(125.5,301,125.5,311)
	line(127.5,300,129.5,311)
	//EYES PAINTING///////////////////////
	fill(255,213,93)
	quad(270,90,326,119,326,257,270,230)
	//inner
	fill(20)
	quad(277,103,319,124,319,246,277,226)
	//bottom
	fill(210,167,50)
	quad(277,226,281,224,319,241.5,319,246)
	//side left
	quad(277,103,281,105,281,224,277,226)
	//top
	fill(162,118,1)
	quad(270.5,90,276,88.5,331,117,326,119)
	//side right
	quad(326,119,331,117,331,255,326,257)
	//top eye
	let x1 = map(mouseX, 100, 400, 294, 304, true);
	let y3 = map(mouseY, 100, 400, 150, 160, true);
	fill(207, 214, 214)
	ellipse(299,155,30,33)//white
	fill(67,124,135)
	ellipse(x1,y3,17,17)//blue
	fill(10)
	ellipse(x1,y3,10,10)//black
	//bottom eye
	let x2 = map (mouseX, 100,400,294,304, true);
	let y4 = map (mouseY, 100,400,195,205, true);
	fill(207, 214, 214)
	ellipse(299,200,30,33)
	fill(67,124,135)
	ellipse(x2,y4,17,17)
	fill(10)
	ellipse(x2,y4,10,10)
	//SPIDER////////////////////
	//string
	let string = map(mouseY,200,400,265,310,true);
	stroke(207, 214, 214)
	line(402,242,402,string)
	//body
	let body = map(mouseY,200,400,268,310,true);
	stroke(0)
	fill(0)
	ellipse(402,body,11,11)
	//left legs
	let leg11andleg21 = map(mouseY,200,400,265,307,true);
	let leg12 = map(mouseY,200,400,258,300,true);
	let leg22 = map (mouseY, 200,400,262,304,true);
	let leg31 = map (mouseY,200,400,268,310,true);
	let leg32 = map (mouseY, 200,400,267,309,true);
	let leg41 = map (mouseY,200,400,270,312,true);
	let leg42 = map (mouseY,200,400,275,317,true);
	line(400,leg11andleg21,392,leg12)
	line(399,leg11andleg21,389,leg22)
	line(398,leg31,389,leg32)
	line(399,leg41,393,leg42)
	//right legs
	let leg51and61 = map(mouseY,200,400,265,307,true);
	let leg52 = map(mouseY,200,400,259,302,true);
	let leg62 = map(mouseY,200,400,264,306,true);
	let leg71and72 = map(mouseY,200,400,268,310,true);
	let leg81 = map(mouseY,200,400,270,312,true);
	let leg82 = map(mouseY, 200,400,275,317,true)
	line(403,leg51and61,411,leg52)
	line(407,leg51and61,413,leg62)
	line(407,leg71and72,414,leg71and72)
	line(406,leg81,411,leg82)
	//eyes
	fill(207, 214, 214)
	let eye = map(mouseY,200,400,269,310,true);
	ellipse(400,eye,4,5)
	ellipse(405,eye,4,5)
	fill(0)
	ellipse(401,eye,2,2)
	ellipse(406,eye,2,2)
	//SHELF////////////////////////////
	fill(67, 40, 26)
	quad(345,220,360,211,409,233,393,242)
	fill(82, 48, 31)
	quad(345,220,345,225,393,247,393,242)
	fill(46, 27, 17)
	quad(393,247,393,242,409,233,409,238)
	//CANDELABRA////////////////////////////
	//fire
	stroke(0,ghost)
	fill(random(207), 37, 1,ghost)
	ellipse(360,176,4,7)
	ellipse(377,160,4,7)
	ellipse(394,184,4,7)
	stroke(0)
	//candle
	rectMode(CENTER);
	fill(246, 229, 195)
	rect(360,188,5,15)
	rect(377,172,5,15)
	rect(394,196,5,15)
	//silver
	fill(207, 214, 214)
	ellipse(377,225,15,10)
	rect(377,205,5,40)
	rect(377,185,8,10)
	rect(360,200,8,10)
	quad(360,199,360,203,374.5,199,374.5,195)
	quad(379.5,195,379.5,200,394,212,394,207)
	rect(394,208,8,10)
	line(360,182,360,177)
	line(377,166,377,161)
	line(394,190,394,185)
	//GHOST//////////////////////////
	stroke(0,ghost)
	fill(207, 214, 214,ghost)
	arc(290.5,324.1, 55, 100, radians(184), radians(-38), OPEN);
	beginShape();
	curveVertex(288,275)
	vertex(316,304)
	curveVertex(336,401)
	vertex(319,396)
	vertex(308,408)
	vertex(293,399)
	vertex(285,412)
	vertex(273,404)
	vertex(261,417)
	vertex(263,322)
	vertex(257,337)
	endShape();
	//face
	fill(0,ghost)
	ellipse(276,309,10,10)
	ellipse(298,308,10,10)
	ghost = ghost + 0.7
	stroke(0)
}
function mousePressed() {
	print("\n", "X=", mouseX, "Y=", mouseY);
}