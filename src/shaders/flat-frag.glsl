#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

//GUI elements
// uniform float u_TimeOfDay; 
// uniform float u_SpeedOfCycle; 
// uniform vec3 u_StadiumColor; 
// uniform float u_AnimatePlatforms; 

in vec2 fs_Pos;
out vec4 out_Col;

const int RAY_STEPS = 100;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float EPSILON = 0.0001;
const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;


// Capped Cylinder
float cappedCylinderSDF( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

//SDF functions
float sphereSDF(vec3 point, float r){
  return length(point) - r;
}

//hexagonal prism
float hexagonalPrismSDF( vec3 p, vec2 h )
{
  const vec3 k = vec3(-0.8660254, 0.5, 0.57735);
  p = abs(p);
  p.xy -= 2.0*min(dot(k.xy, p.xy), 0.0)*k.xy;
  vec2 d = vec2(
       length(p.xy-vec2(clamp(p.x,-k.z*h.x,k.z*h.x), h.x))*sign(p.y-h.x),
       p.z-h.y );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

// Ellipsoid
float ellipsoidSDF(in vec3 p, in vec3 r)
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0 * (k0 - 1.0) / k1;
}

//Box
float boxSDF( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

//Round Box
float roundBoxSDF( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

//Capsule 
float verticalCapsuleSDF( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}

//round cone 
float roundConeSDF( vec3 p, float r1, float r2, float h )
{
  vec2 q = vec2( length(p.xz), p.y );
    
  float b = (r1-r2)/h;
  float a = sqrt(1.0-b*b);
  float k = dot(q,vec2(-b,a));
    
  if( k < 0.0 ) return length(q) - r1;
  if( k > a*h ) return length(q-vec2(0.0,h)) - r2;
        
  return dot(q, vec2(a,b) ) - r1;
}

//regular cone
float coneSDF( vec3 p, vec2 c, float h )
{
  // c is the sin/cos of the angle, h is height
  // Alternatively pass q instead of (c,h),
  // which is the point at the base in 2D
  vec2 q = h*vec2(c.x/c.y,-1.0);
    
  vec2 w = vec2( length(p.xz), p.y );
  vec2 a = w - q*clamp( dot(w,q)/dot(q,q), 0.0, 1.0 );
  vec2 b = w - q*vec2( clamp( w.x/q.x, 0.0, 1.0 ), 1.0 );
  float k = sign( q.y );
  float d = min(dot( a, a ),dot(b, b));
  float s = max( k*(w.x*q.y-w.y*q.x),k*(w.y-q.y)  );
  return sqrt(d)*sign(s);
}

float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }

//rhombus SDF
float rhombusSDF(vec3 p, float la, float lb, float h, float ra)
{
  p = abs(p);
  vec2 b = vec2(la,lb);
  float f = clamp( (ndot(b,b-2.0*p.xz))/dot(b,b), -1.0, 1.0 );
  vec2 q = vec2(length(p.xz-0.5*b*vec2(1.0-f,1.0+f))*sign(p.x*b.y+p.z*b.x-b.x*b.y)-ra, p.y-h);
  return min(max(q.x,q.y),0.0) + length(max(q,0.0));
}


float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

//Union
float unionOp( float d1, float d2){
    return smin(d1,d2, 0.1); // smooth
}

//subtraction 
// d1 - d2
float subtractOp( float d1, float d2 ){
    return max(-d1,d2);
}

//Intersection 
float intersectOp( float d1, float d2 ){
    return max(d1,d2);
}

// rotation
vec2 rot(vec2 v, float y){
    return cos(y)*v + sin(y)*vec2(-v.y, v.x);
}

//raycasting function 
vec3 rayCast(vec3 eye) {

  vec3 forward = normalize(u_Ref - eye);
  vec3 right = normalize(cross(forward, u_Up));

  float FOVY = 45.0; 
  float angleTerm = tan(FOVY / 2.0);
  float aspectRatio = u_Dimensions.x / u_Dimensions.y; 
  vec3 V = (u_Up) * angleTerm;
  vec3 H = right * aspectRatio * angleTerm;
  vec3 point = forward + (fs_Pos.x * H) + (fs_Pos.y * V);

  return normalize(point);

}

// get the closest sdf
// pick the vector for the closests object so you grab the correct color along with position
vec3 closestVec(vec3 a, vec3 b){
    if (a.x < b.x) {
        return a;
    }
    return b;
}

//rotations -- https://gist.github.com/onedayitwillmake/3288507 
mat4 rotationX(float angle ) {
	return mat4(	1.0,		0,			0,			0,
			 		0, 	cos(angle),	-sin(angle),		0,
					0, 	sin(angle),	 cos(angle),		0,
					0, 			0,			  0, 		1);
}

mat4 rotationY( float angle ) {
	return mat4(	cos(angle),		0,		sin(angle),	0,
			 				0,		1.0,			 0,	0,
					-sin(angle),	0,		cos(angle),	0,
							0, 		0,				0,	1);
}

mat4 rotationZ( float angle ) {
	return mat4(	cos(angle),		-sin(angle),	0,	0,
			 		sin(angle),		cos(angle),		0,	0,
							0,				0,		1,	0,
							0,				0,		0,	1);
}


//angle in degrees 
vec3 rotatePosX(vec3 pos, float angle) {
  mat3 rotMat = mat3(rotationX(radians(angle))); 
  return inverse(rotMat) * pos; 
}

vec3 rotatePosY(vec3 pos, float angle) {
  mat3 rotMat = mat3(rotationY(radians(angle))); 
  return inverse(rotMat) * pos; 
}

vec3 rotatePosZ(vec3 pos, float angle) {
  mat3 rotMat = mat3(rotationZ(radians(angle))); 
  return inverse(rotMat) * pos; 
}

//toolbox functions 
float sawtooth_wave(float x, float freq, float amplitude) {
  return (x * freq - floor(x * freq)) * amplitude; 
}

float triangle_wave(float x, float freq, float amplitude) {
  return abs(mod((x * freq), amplitude) - (0.5 * amplitude)); 
}

// SceneSDF
// in the vec3 being returned .x is the float, .y is the color ID
vec3 sceneSDF(vec3 point){  

  //Pikachu
  vec3 pos = vec3(point.x, point.y - 2.0, point.z - 10.0);
  float pikachu = sphereSDF(pos, 1.9); // Pikachu

  vec3 faceExtension = pos + vec3(0.0, 0.8, 0.0); 
  float fe = ellipsoidSDF(faceExtension, vec3(2.3, 1.5, 2.0) / 1.1); //face chub
  pikachu = unionOp(pikachu, fe);
  float fe2 = ellipsoidSDF(faceExtension + vec3(0.0, 0.0, 0.5), vec3(2.2, 1.4, 1.8) / 1.1); //adds even more face chub for nose-ish area
  pikachu = unionOp(pikachu, fe2);

  pos.y += 3.0; 
  float pikachuBody = verticalCapsuleSDF(pos, 3.0, 1.5); 
  pikachuBody = ellipsoidSDF(pos, vec3(2.3, 3.0, 2.0) / 1.25);
  pikachu = unionOp(pikachu, pikachuBody); //Pikachu's body 

  pos = pos + vec3(1.0, 2.0, 0.5);  
  vec3 rotated = pos; 
  rotated.yz = rot(rotated.yz, 3.0); 
  vec3 rl = rotated; 
  float rightLeg = verticalCapsuleSDF(rotated, 1.0, 1.0); //right leg 
  pikachu = unionOp(pikachu, rightLeg); 

  float pikachuRightFoot = ellipsoidSDF(pos + vec3(0.0, 2.0, 0.5), vec3(0.8, 0.5, 1.5) * 0.8); //right foot 
  pikachu = unionOp(pikachu, pikachuRightFoot); 

  pos.x -= 2.0;  //making it opposite to left leg 
  rotated = pos; 
  rotated.yz = rot(rotated.yz, 3.0);
  vec3 ll = rotated;  
  float leftLeg = verticalCapsuleSDF(rotated, 1.0, 1.0); //leftLeg
  pikachu = unionOp(pikachu, leftLeg); 

  float pikachuLeftFoot = ellipsoidSDF(pos + vec3(0.0, 2.0, 0.5), vec3(0.8, 0.5, 1.5) * 0.8); //left foot 
  pikachu = unionOp(pikachu, pikachuLeftFoot); 

  //do arms here
    //replace raymarchPos with the input point 
  // 1) pos = raymarchPos + (offset to move pivot of ellipsoid to origin)
  // 2) pos = rotate(pos, inverseRot)
  // 3) pos = pos - offset_from_1
  // 4) pos += translate to put arm in correct location
  // 5) rightArm = SDF(pos);
  rotated = rl + vec3(0.5, 2.5, 0.0); 
  float rightArm = verticalCapsuleSDF(rotated, 1.0, 1.0); //right arm
  rightArm =  ellipsoidSDF(rotated, vec3(2.5, 0.8, 1.0) * 0.9);
  pikachu = unionOp(pikachu, rightArm);

  rotated = ll + vec3(-0.5, 2.5, 0.0); 
  float leftArm = verticalCapsuleSDF(rotated, 1.0, 1.0); //left arm 
  leftArm = ellipsoidSDF(rotated, vec3(2.5, 0.8, 1.0) * 0.9);
  pikachu = unionOp(pikachu, leftArm);


  pos = vec3(point.x, point.y + 2.8, point.z - 10.0); //reset back to pikachu's head position 
  float bottomChub =  ellipsoidSDF(pos, vec3(2.0, 1.8, 2.0) / 1.0); //bottom chub
  pikachu = unionOp(pikachu, bottomChub); 
  bottomChub = roundConeSDF(pos, 2.0, 1.5, 2.0); //another addition to smooth out the bottom chub even more 
  pikachu = unionOp(pikachu, bottomChub); 

  //ears 
  pos.y += -10.0; 
  vec3 storePikaEarPos = pos; 
  vec3 earPosPika = pos + vec3(2.0, 2.5, 0.0); 
  earPosPika = rotatePosZ(earPosPika, -30.0); 
  float topHalf = roundConeSDF(earPosPika, 0.5, 0.2, 1.15);
  float blackTip = roundConeSDF(earPosPika + vec3(0.0, -0.3, 0.0), 0.5, 0.20, 1.15); 
  pos.y += 1.5; 
  earPosPika.y += 1.5;
  float bottomHalf = roundConeSDF(earPosPika, 0.2, 0.5, 1.15);
  float ear1 = unionOp(topHalf, bottomHalf); 

  earPosPika = storePikaEarPos + vec3(-2.0, 2.5, 0.0); 
  earPosPika = rotatePosZ(earPosPika, 30.0); 
  topHalf = roundConeSDF(earPosPika, 0.5, 0.2, 1.15);
  float blackTip2 = roundConeSDF(earPosPika + vec3(0.0, -0.3, 0.0), 0.5, 0.20, 1.15); 
  earPosPika.y += 1.5;
  bottomHalf = roundConeSDF(earPosPika, 0.2, 0.5, 1.15);
  float ear2 = unionOp(topHalf, bottomHalf); 
  ear1 = unionOp(ear1, ear2); 
  blackTip = unionOp(blackTip, blackTip2); 

  //eyes
  pos += vec3(0.8, 3.5, 1.5); 
  vec3 tempPos = pos; 
  float pikachuEye = ellipsoidSDF(pos, vec3(0.45)); //right eye 
  float pikachuEyewhite = ellipsoidSDF(pos + vec3(-0.05, -0.1, 0.2), vec3(0.25)); 

  pos += vec3(-1.5, 0.0, 0.0); 
  float pikachuEye2 = ellipsoidSDF(pos, vec3(0.45)); //left eye 
  float pikachuEyewhite2 = ellipsoidSDF(pos + vec3(0.05, -0.1, 0.2), vec3(0.25)); 
  pikachuEye = unionOp(pikachuEye, pikachuEye2); 
  pikachuEyewhite = unionOp(pikachuEyewhite, pikachuEyewhite2); 

  //cheeks
  pos += vec3(-0.45, 1.0, -0.2);
  float cheeks = ellipsoidSDF(pos, vec3(0.6, 0.5, 0.6) + 0.05); //left cheek 

  pos = tempPos + vec3(0.45, 1.0, -0.2);
  float cheekRight = ellipsoidSDF(pos, vec3(0.6, 0.5, 0.6) + 0.05); //right cheek 
  cheeks = unionOp(cheeks, cheekRight); 


  //nose
  pos = vec3(point.x, point.y - 1.5, point.z - 8.0); //reset position to pikachu
  float pikachuNose = ellipsoidSDF(pos, vec3(1.2, 1.0, 1.0) * 0.15); 


  //----------------------
  //Pichu 
  pos = vec3(point.x - 10.0, point.y, point.z - 10.0); //reset position to pikachu
  pos.x += 2.0; 
  vec3 originalPos = pos; //store this position for later 
  float pichu = ellipsoidSDF(pos, vec3(3.0, 2.5, 2.0) * 0.7); //pichu's head 

  pos += vec3(0.0, 3.2, 0.0); 
  float pichuBody = ellipsoidSDF(pos, vec3(2.2, 3.0, 2.0) * 0.7); //pichu's body 
  pichu = unionOp(pichu, pichuBody);

  pos += vec3(-1.0, -1.0, 0.0); 
  float pichuLeftArm = ellipsoidSDF(pos, vec3(3.0, 0.8, 1.0) * 0.7); //pichu's left arm 
  pichu = unionOp(pichu, pichuLeftArm);

  pos += vec3(2.0, 0.0, 0.0); 
  float pichuRightArm = ellipsoidSDF(pos, vec3(3.0, 0.8, 1.0) * 0.7); //pichu's right arm 
  pichu = unionOp(pichu, pichuRightArm);

  pos += vec3(0.0, 2.8, 1.0); 
  float pichuRightFoot = ellipsoidSDF(pos, vec3(0.8, 0.5, 1.5) * 0.7); //pichu's right foot 
  pichu = unionOp(pichu, pichuRightFoot);

  pos += vec3(-2.0, 0.0, 0.0);
  float pichuLeftFoot = ellipsoidSDF(pos, vec3(0.8, 0.5, 1.5) * 0.7); //pichu's left foot 
  pichu = unionOp(pichu, pichuLeftFoot);

  pos = originalPos; //reset back to face
  pos += vec3(1.0, -0.15, 0.95);
  float pichuEye = ellipsoidSDF(pos, vec3(0.45, 0.55, 0.45)); //right eye 
  float pichuEyewhite = ellipsoidSDF(pos + vec3(0.01, -0.18, 0.2), vec3(0.25, 0.28, 0.25)); //right eye white 

  pos += vec3(-2.0, 0.0, 0.0);
  float pichuEye2 = ellipsoidSDF(pos, vec3(0.45, 0.55, 0.45)); //left eye 
  pichuEye = unionOp(pichuEye, pichuEye2); 
  float pichuEyewhite2 = ellipsoidSDF(pos + vec3(0.01, -0.18, 0.2), vec3(0.25, 0.28, 0.25)); //left eye white 
  pichuEyewhite = unionOp(pichuEyewhite, pichuEyewhite2); 

  pos = originalPos; //reset back to face 
  pos += vec3(0.0, 0.0, 1.3); 
  float pichuNose = ellipsoidSDF(pos, vec3(1.2, 1.0, 1.0) * 0.15); 
  pichuNose = ellipsoidSDF(pos, vec3(1.2, 1.0, 1.0) * 0.15); 

  pos += vec3(-1., 0.55, -0.68);
  float pichuCheek = ellipsoidSDF(pos, vec3(0.6, 0.65, 0.55)); //left cheek 

  pos += vec3(2.0, 0.0, 0.0);
  float pichuCheek2 = ellipsoidSDF(pos, vec3(0.6, 0.65, 0.55)); //right cheek 
  pichuCheek = unionOp(pichuCheek, pichuCheek2); 

  //Pichu's ears 
  pos += vec3(0.0, -3.0, 0.0);
  //rotate by 90 degrees
  vec3 earPos = rotatePosX(pos, 90.0); 
  earPos = rotatePosY(earPos, 25.0); 
  earPos += vec3(1.0, 1.0, 0.0); 
  float pichuEar = rhombusSDF(earPos, 0.5, 0.8, 0.05, 0.5); //right ear
  pichu = unionOp(pichu, pichuEar); 

  earPos = pos + vec3(-2.0, 0.0, 0.0); 
  earPos = rotatePosX(earPos, 90.0); 
  earPos = rotatePosY(earPos, -25.0); 
  earPos += vec3(-1.0, 1.0, 0.0);
  float pichuEar2 = rhombusSDF(earPos, 0.5, 0.8, 0.05, 0.5); //left ear
  pichu = unionOp(pichu, pichuEar2); 

  

  //----------
  //Pokemon Stadium 
  pos = vec3(point.x, point.y + 6.18, point.z - 7.0);
  originalPos = pos; //store pos 
  float stadiumGrey = roundBoxSDF(pos, vec3(27.0, 0.3, 14.0), 0.5); //first level 

  pos += vec3(0.0, 2.0, 0.0); 
  float secondLevel = roundBoxSDF(pos, vec3(27.0, 0.3, 14.0) * 0.7, 0.5);  //second level 
  stadiumGrey = unionOp(stadiumGrey, secondLevel); 

   pos += vec3(0.0, 2.0, 0.0); 
  float thirdLevel = roundBoxSDF(pos, vec3(27.0, 0.3, 14.0) * 0.4, 0.5);  //third level 
  stadiumGrey = unionOp(stadiumGrey, thirdLevel); 

  pos += vec3(0.0, 3.0, 0.0); 
  float tube = hexagonalPrismSDF(pos, vec2(2.0));  //tube thing at bottom 
  stadiumGrey = unionOp(stadiumGrey, tube); 

  pos = originalPos; 
  //pos += vec3(0.0, -0.1, 0.0); 
  float stadiumGreen = roundBoxSDF(pos, vec3(33.0, 0.7, 17.0) * 0.7, 0.5); //green floor of stadium 

  //add floating panels 
  vec3 store = pos; 
  pos += vec3(18.0, -7.0, -1.0); 
  vec3 animateAddRight = vec3(0.0, 0.0, 0.0);
  // if (u_AnimatePlatforms == 1.0) {
  //   float y_val = triangle_wave(u_Time / 5.0, 1.0, 8.0); //amplitude is 8 because I want it between -4 and 4
  //   animateAddRight = vec3(0.0, y_val, 0.0); //use to animate RIGHT platform
  // }
  
  float rightPanel = roundBoxSDF(pos + animateAddRight, vec3(5.0, 0.1, 3.0), 0.3); //right panel grey 
  stadiumGrey = unionOp(stadiumGrey, rightPanel); 

  pos.y -= 0.2; 
  float rightPanelGreen = roundBoxSDF (pos + animateAddRight, vec3(5.0, 0.1, 3.0) * 0.8, 0.2); //right panel green
  stadiumGreen = unionOp(stadiumGreen, rightPanelGreen); 

  pos = store; 
  pos += vec3(-18.0, -7.0, -1.0); 
  vec3 animateAddLeft = vec3(0.0, 0.0, 0.0);
  // if (u_AnimatePlatforms == 1.0) {
  //   float y_val = triangle_wave(u_Time / 5.0, 1.0, 8.0);
  //   animateAddLeft = vec3(0.0, y_val, 0.0); //use to animate RIGHT platform
  // }
  float leftPanel = roundBoxSDF(pos + animateAddLeft, vec3(5.0, 0.1, 3.0), 0.3); //left panel grey 
  stadiumGrey = unionOp(stadiumGrey, leftPanel); 

  pos.y -= 0.2; 
  float leftPanelGreen = roundBoxSDF (pos + animateAddLeft, vec3(5.0, 0.1, 3.0) * 0.8, 0.2); //left panel green
  stadiumGreen = unionOp(stadiumGreen, leftPanelGreen);  

  //add pokeball
  pos = point + vec3(0.0, 5.3, -7.0); //reset the position 
  
  float redPokeball = cappedCylinderSDF(pos, 9.0, 0.2); 

  float subtractBox = boxSDF(pos + vec3(-5.0, 0.0, 0.0), vec3(5.0, 0.3, 9.5));
  redPokeball = subtractOp(subtractBox, redPokeball); 
  
  float blackStrip = boxSDF(pos, vec3(0.3, 0.2, 9.0));

  //pos.y += 1.0; 
  float whitePokeball = cappedCylinderSDF(pos, 9.0, 0.15);
  whitePokeball = subtractOp(redPokeball, whitePokeball); 
  whitePokeball = subtractOp(blackStrip, whitePokeball); 

  pos.y += -0.3; 
  float blackCircle = cappedCylinderSDF(pos, 1.5, 0.15);
  blackStrip = unionOp(blackStrip, blackCircle); 

  pos.y += -0.05; 
  float whiteCircle = cappedCylinderSDF(pos, 1.2, 0.15);
  whitePokeball = unionOp(whitePokeball, whiteCircle); 


  //------------------------ 
  // drawing and coloring
  
  //pokemon stuff
  //PIKACHU 
  vec3 currVec = vec3(pikachu, 2.0, 0.0); 
  currVec = closestVec(currVec, vec3(pikachu, 2.0, 0.0)); //pikachu has color ID 2.0 
  currVec = closestVec(currVec, vec3(ear1, 2.0, 0.0)); //pikachu has color ID 2.0 
  currVec = closestVec(currVec, vec3(blackTip, 1.0, 0.0)); //pikachu ear tips are black with color ID 1.0 
  currVec = closestVec(currVec, vec3(pikachuEye, 1.0, 0.0)); //pikachu eye is black with color ID 1.0 
  currVec = closestVec(currVec, vec3(pikachuEyewhite, 3.0, 0.0)); //pikachu eye whites are white with color ID 3.0  
  currVec = closestVec(currVec, vec3(pikachuNose, 1.0, 0.0)); //pikachu ear tips are black with color ID 1.0 
  currVec = closestVec(currVec, vec3(cheeks, 4.0, 0.0)); //pikachu cheeks red with color ID 4.0 

  //PICHU
  currVec = closestVec(currVec, vec3(pichu, 2.0, 0.0)); //pichu has color ID 2.0
  currVec = closestVec(currVec, vec3(pichuEye, 1.0, 0.0)); //pichu has color ID 1.0
  currVec = closestVec(currVec, vec3(pichuEyewhite, 3.0, 0.0)); //pichu has color ID 3.0
  currVec = closestVec(currVec, vec3(pichuNose, 1.0, 0.0)); //pichu has color ID 1.0
  currVec = closestVec(currVec, vec3(pichuCheek, 5.0, 0.0)); //pichu has color ID 5.0

  //STADIUM 
  currVec = closestVec(currVec, vec3(stadiumGrey, 6.0, 0.0)); //stadium grey has color ID 6.0
  currVec = closestVec(currVec, vec3(stadiumGreen, 7.0, 0.0)); //stadium green has color ID 7.0
  // currVec = closestVec(currVec, vec3(redPokeball, 4.0, 0.0)); //red pokeball has color ID 4.0
  // currVec = closestVec(currVec, vec3(blackStrip, 8.0, 0.0)); //black strip has color ID 1.0 
  // currVec = closestVec(currVec, vec3(whitePokeball, 3.0, 0.0)); //white pokeball has color ID 3.0 

  return currVec;
}

// calculate normals
//source http://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/#surface-normals-and-lighting 
vec3 getNormals(vec3 pos) {
   vec3 eps = vec3(0.0, 0.001, 0.0);
    vec3 normals =  normalize(vec3(
        sceneSDF(vec3(pos + eps.yxz)).x - sceneSDF(vec3(pos - eps.yxz)).x,
        sceneSDF(vec3(pos + eps.xyz)).x - sceneSDF(vec3(pos - eps.xyz)).x,
        sceneSDF(vec3(pos + eps.xzy)).x - sceneSDF(vec3(pos - eps.xzy)).x
    ));
   return normals;
}

vec3 rayMarchFunction(vec3 origin, vec3 marchDir, float start, float end){
  float t = 0.001;
  vec3 sdfVec = vec3(0.0);
  float colorID = 0.0;
  float distVar = 0.0;
  float depth = start;
      
  for (int i = 0; i < RAY_STEPS; i ++){
    vec3 pos = origin + depth * marchDir;
    sdfVec = sceneSDF(pos);
    distVar = sdfVec.x; // the minimum distance
    colorID = sdfVec.y; // the color ID
    if(distVar < EPSILON){ //less than some threshold epsilon 
      return vec3(depth, colorID, 0.0);
    }
    depth += distVar;
    if(depth >= end){
      return vec3(end, colorID, 0.0);
    }
  } 

  return vec3(end, colorID, 0.0);

}

vec3 getColor(float id, float lightMult, float specVal, vec3 point) {
  vec3 coloring = vec3(0.0);
        

    // pikachu ear tip 
    if (id == 1.0){
        coloring = vec3(0.043, 0.055, 0.0) * lightMult + specVal;
        return coloring;
    } else if (id == 2.0) {
      //Pikachu - yellow 
      coloring = vec3(245.0, 224.0, 66.0) / 255.0; 
      coloring = coloring * lightMult; 
      return coloring;

    } else if (id == 3.0) {
      //pikachu - white 
      coloring = vec3(255.0, 255.0, 255.0) / 255.0; 
      //coloring = coloring * lightMult * specVal; 
      return coloring * lightMult; 
    } else if (id == 4.0) {
      //pikachu's cheeks are red
      coloring = vec3(209.0, 33.0, 45.0) / 255.0; 
      coloring = coloring * lightMult;
      return coloring;

    } else if (id == 5.0) {
      //pichu's cheeks are pink
      coloring = vec3(242.0, 145.0, 182.0) / 255.0; 
      coloring = coloring * lightMult;
      return coloring;

    } else if (id == 6.0) {
      //stadium grey
      coloring = vec3(102.0, 95.0, 95.0) / 255.0; 
      coloring = coloring * lightMult; 
      return coloring;

    } else if (id == 7.0) {
      //stadium green 
      // coloring = vec3(50.0, 102.0, 20.0) / 255.0; 
      // coloring = coloring * lightMult;
      return vec3(-1.0, -1.0, -1.0); // REFLECTIVITY 
    } else if (id == 8.0) {
      //stadium black lambert 
      coloring = vec3(0.043, 0.055, 0.0) * lightMult;
        return coloring;

    }
    
    return vec3(id / 10.0);
}


//background stuff
float rand(vec2 co)
{
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

//from minecraft code
// spherical coordinate to uv
// project texture to a sphere

// sunset palette
const vec3 sunset[5] = vec3[](vec3(255, 229, 119) / 255.0, // yellow
                            vec3(254, 192, 81) / 255.0, // orange
                            vec3(255, 137, 103) / 255.0, // grapefruit
                            vec3(253, 96, 81) / 255.0, // rose pink
                            vec3(57, 32, 51) / 255.0); // dark purple

                            // dusk palette
const vec3 dusk[5] = vec3[](vec3(144, 96, 144) / 255.0, // light purple
                            vec3(96, 72, 120) / 255.0, // purple grape
                            vec3(72, 48, 120) / 255.0, // dark blue
                            vec3(48, 24, 96) / 255.0, // dark night
                            vec3(0, 24, 72) / 255.0); // dark cyan

// dusk palette
const vec3 noon[5] = vec3[] (vec3(204, 240, 255) / 255.0,
                            vec3(178, 232, 255) / 255.0,
                            vec3(153, 225, 255) / 255.0,
                            vec3(127, 218, 255) / 255.0,
                            vec3(102, 210, 255) / 255.0);

const vec3 sunrise[5] = vec3[](vec3(255,215,0) / 255.0,
                            vec3(255,165,0) / 255.0,
                            vec3(255,140,0) / 255.0,
                            vec3(255,127,80) / 255.0,
                            vec3(255,99,71) / 255.0);

const vec3 sunColor = vec3(255, 255, 190) / 255.0;
const vec3 cloudColor = sunset[3];

vec3 uvToSunrise(vec2 uv) {
    if (uv.y < 0.5) {
        return sunrise[0];
    } else if (uv.y < 0.55) {
        return mix(sunrise[0], sunrise[1], (uv.y - 0.5) / 0.05);
    } else if (uv.y < 0.6) {
        return mix(sunrise[1], sunrise[2], (uv.y - 0.55) / 0.05);
    } else if (uv.y < 0.65) {
        return mix(sunrise[2], sunrise[3], (uv.y - 0.6) / 0.05);
    } else if (uv.y < 0.75) {
        return mix(sunrise[3], sunrise[4], (uv.y - 0.65) / 0.1);
    }
    return sunrise[4];
}

vec3 uvToNoon(vec2 uv) {
    if (uv.y < 0.5) {
        return noon[0];
    } else if (uv.y < 0.55) {
        return mix(noon[0], noon[1], (uv.y - 0.5) / 0.05);
    } else if (uv.y < 0.6) {
        return mix(noon[1], noon[2], (uv.y - 0.55) / 0.05);
    } else if (uv.y < 0.65) {
        return mix(noon[2], noon[3], (uv.y - 0.6) / 0.05);
    } else if (uv.y < 0.75) {
        return mix(noon[3], noon[4], (uv.y - 0.65) / 0.1);
    }
    return noon[4];
}


// spherical coordinate to uv
// project texture to a sphere
vec2 sphereToUV(vec3 p) {

    float phi = atan(p.z, p.x);
    if (phi < 0.0) {
        phi += TWO_PI;
    }

    float theta = acos(p.y);

    return vec2(1.0 - phi / TWO_PI, 1.0 - theta / PI);
}

// map uv to sunset palette
// assign colors based on y coordinate of uv
// interpolate between predefined intervals
vec3 uvToSunset(vec2 uv) {
    if (uv.y < 0.5) {
        return sunset[0];
    } else if (uv.y < 0.55) {
        return mix(sunset[0], sunset[1], (uv.y - 0.5) / 0.05);
    } else if (uv.y < 0.6) {
        return mix(sunset[1], sunset[2], (uv.y - 0.55) / 0.05);
    } else if (uv.y < 0.65) {
        return mix(sunset[2], sunset[3], (uv.y - 0.6) / 0.05);
    } else if (uv.y < 0.75) {
        return mix(sunset[3], sunset[4], (uv.y - 0.65) / 0.1);
    }
    return sunset[4];
}

// map uv to dusk palette
vec3 uvToDusk(vec2 uv) {
    if(uv.y < 0.5) {
        return dusk[0];
    }
    else if(uv.y < 0.55) {
        return mix(dusk[0], dusk[1], (uv.y - 0.5) / 0.05);
    }
    else if(uv.y < 0.6) {
        return mix(dusk[1], dusk[2], (uv.y - 0.55) / 0.05);
    }
    else if(uv.y < 0.65) {
        return mix(dusk[2], dusk[3], (uv.y - 0.6) / 0.05);
    }
    else if(uv.y < 0.75) {
        return mix(dusk[3], dusk[4], (uv.y - 0.65) / 0.1);
    }
    return dusk[4];
}

//mapping function to map something from min max to another min max 
//reference: https://gamedev.stackexchange.com/questions/147890/is-there-an-hlsl-equivalent-to-glsls-map-function 
float map_range(float v, float min1, float max1, float min2, float max2) {
        // Convert the current value to a percentage
    // 0% - min1, 100% - max1
    float perc = (v - min1) / (max1 - min1);

    // Do the same operation backwards with min2 and max2
    float newV = perc * (max2 - min2) + min2;

    return newV; 
}


vec4 getMorningColor(vec3 rayDir) {
  vec2 uv = sphereToUV(rayDir); 

   // compute a gradient from the bottom of the sky-sphere to the top

    // uv is not noise, uv is perturbed by noise
    vec3 sunsetColor = uvToSunset(uv); //+ offset * 0.1);
    vec3 duskColor = uvToDusk(uv); //+ offset * 0.1);
    vec3 noonColor = uvToNoon(uv);
    vec3 sunriseColor = uvToSunrise(uv);

    //fastest = 0.0008
    //slowest = 0.00001
    //map 0 to 100 to these values 
    float factor = map_range(0.00008, 0.0, 100.0, 0.00001, 0.0008); 

    // add a glowing sun in the sky
    // direction pointing from origin to the sun
    
    //factor = 0.00005; //change this for day cycle speed
    float cos_sun = cos(degrees(u_Time * factor));
    float sin_sun = sin(degrees(u_Time * factor));
    vec3 sunDir = normalize(vec3(cos_sun, sin_sun, 1.0));

    float sunSize = 30.0; // in degrees

    vec3 outColor; 

    // angle between our ray dir and dir pointing to the center of sun
    float angle = acos(dot(rayDir, sunDir)) * 360.0 / PI;

    vec3 skyColor;
    if (sin_sun > 0.85) {
        // noon
        skyColor = noonColor;
    } else if (sin_sun > 0.55) {
        // 0.55 ~ 0.85
        if (cos_sun > 0.0) {
            skyColor = mix(noonColor, sunriseColor, (0.85 - sin_sun) / 0.3);
        } else {
            skyColor = mix(noonColor, sunsetColor, (0.85 - sin_sun) / 0.3);
        }

    } else if (sin_sun > 0.15) {
        // 0.15 ~ 0.55
        if (cos_sun > 0.0) {
            skyColor = sunriseColor;
        } else {
            skyColor = sunsetColor;
        }

    } else if (sin_sun > -0.15) {
        // -0.15 ~ 0.15
        if (cos_sun > 0.0) {
            skyColor = mix(sunriseColor, duskColor, (0.15 - sin_sun) / 0.3);
        } else {
            skyColor = mix(sunsetColor, duskColor, (0.15 - sin_sun) / 0.3);
        }

    } else {
        skyColor = duskColor;
    }

    // if the angle between our ray dir and vector to center of sunColor
    // is less than the threshold, we're looking at the sun

    // go from looking at the sun
    // to corona
    // to sunset color, (sampled from sunset palette)
    // to interp between sunset and dusk color
    // to complete dusk color
    if (angle < sunSize) {
        // full center of sun
        if (angle < 7.5) {
            outColor = sunColor;
        } else {
            // corona of sun, mix with sky color
            // sunset color: noise perturbed uv on sunset palette
            // sky around the sun is affected by suncolor
            // 7.5 - 30 degrees
            outColor = mix(sunColor, skyColor, (angle - 7.5) / 22.5);
        }
    } else {
        outColor = skyColor;
    }

    return vec4(outColor, 1.0); 


}


vec4 getBackgroundColor(vec2 st) { //used reference for starry night https://www.shadertoy.com/view/tdlBRf 
  float size = 30.0; 
  float prob = 0.95; 
  vec2 fragCoord = fs_Pos; 
  fragCoord = st; 
  vec2 pos = floor(1.0 / size * fragCoord.xy);

  float color = 0.0;
	float starValue = rand(pos);

  float time = u_Time * 10.0; 
  if (starValue > prob)
		{
			vec2 center = size * pos + vec2(size, size) * 0.5;
		
			float t = 0.9 + 0.2 * sin(time + (starValue - prob) / (1.0 - prob) * 45.0);
				
			color = 1.0 - distance(fragCoord.xy, center) / (0.5 * size);
			color = color * t / (abs(fragCoord.y - center.y)) * t / (abs(fragCoord.x - center.x));
		}
		else if (rand(fragCoord.xy / u_Dimensions.xy) > 0.996)
		{
			float r = rand(fragCoord.xy);
			color = r * (0.25 * sin(time * (r * 5.0) + 720.0 * r) + 0.75);
		}
	
		return vec4(vec3(color), 1.0);

}

//from torrii gate
// generates 1D random numbers for noise functions
float random1(vec2 p) {
    return fract(sin(dot(p,vec2(341.58, 735.42)))
                 *40323.3851);
}

// interpolates 2D noise for fractal brownian
float interpNoise2D(float x, float y) {
    // interpolates 2D based fract (x, y) between curr and next int (x, y)
    int intX = int(floor(x));
    float fractX = fract(x);
    int intY = int(floor(y));
    float fractY = fract(y);
    float i1 = mix(random1(vec2(intX, intY)), random1(vec2(intX + 1, intY)), fractX);
    float i2 = mix(random1(vec2(intX, intY + 1)), random1(vec2(intX + 1, intY + 1)), fractX);
    return mix(i1, i2, fractY);
    
}

// calculates 2D fractal brownian w/ octaves input
float FractalBrownian2D(vec2 p, int octaves, bool animate) {
    // Animate the point
    vec2 point;
    if (animate) {
        point = p + vec2(u_Time * 0.22, u_Time * 0.53);
    } else {
        point = p;
    }
    float total = 0.;
    float persistence = 0.5;
    for (int i = 1; i <= octaves; i++) {
        float freq = pow(2., float(i));
        float amp = pow(persistence, float(i));
        // amplitude decreases as i increases, frequency increases
        total += interpNoise2D(point.x * freq, point.y * freq) * amp;
    }
    return total;
}


// calculates 2D fractal brownian
float FractalBrownian2D(vec2 p, bool animate) {
    return FractalBrownian2D(p, 4, animate);
}

// mat2 for waterMap
const mat2 m2 = mat2( 0.60, -0.80, 0.80, 0.60 );

// modified from https://www.shadertoy.com/view/MsB3WR
// maps water based on x and z of plane
float waterMap( vec2 pos ) {
    float radius = length(pos - u_Eye.xz);
	vec2 posm = pos * m2;
    if (radius > 10. && radius < 50.) {
        return (1. - smoothstep(30., 50., radius)) * (smoothstep(10., 30., radius)) 
            * abs( FractalBrownian2D(vec2(posm), true) - 0.8 )* 0.05;
    } else {
        return 0.;
    }
}


void main() {
  out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);

  vec3 rayDir = rayCast(u_Eye); 
  vec3 outColor = 0.5 * (rayDir + vec3(1.0, 1.0, 1.0));
  out_Col = vec4(outColor, 1.0); 
  //the above gives you the colorful test from the first part of the assignment (testing raycasting)

  vec3 marchVals = rayMarchFunction(u_Eye, rayDir, MIN_DIST, MAX_DIST); 
  vec3 gottenColor = getColor(marchVals.y, 1.0, 1.0, u_Eye + marchVals.x * rayDir); 
  out_Col = vec4(gottenColor, 1.0); 

  float dist = marchVals.x;
  float colorVal = marchVals.y;
  vec3 origIsect = u_Eye + dist * rayDir;
  vec3 isect = origIsect;
  vec3 surfaceColor = vec3(1.);

  if (colorVal == 7.0) {
    //reflectivity 
     // compute normal of waterMap sdf
    vec2 pos = isect.xz;
    vec2 epsilon = vec2( EPSILON, 0. );
    vec3 nor = vec3( 0., 1., 0. );
		 nor.x = (waterMap(pos + epsilon.xy) - waterMap(pos - epsilon.xy) ) / (2. * EPSILON);
		 nor.z = (waterMap(pos + epsilon.yx) - waterMap(pos - epsilon.yx) ) / (2. * EPSILON);
		 nor = normalize( nor );	
    vec3 rayDir2 = reflect(rayDir, normalize(nor));
    //vec3 rayDir2 = dir - 2.0 * dot(nor, dir) * nor; 
    //vec3 rayDir2 = vec3(0.); 
    //march(isect, rayDir, t, hitObj);
    vec3 march2Vals = rayMarchFunction(isect + rayDir2 * 0.01, rayDir2, MIN_DIST, MAX_DIST);
    // re-compute intersection pt & normal
    isect = isect + march2Vals.x * rayDir2;
    nor = getNormals(isect);
    // alter surfaceColor by reflection color
    vec3 reflectColor = getColor(march2Vals.y, 1.0, 1.0, u_Eye + march2Vals.x * rayDir2); 
    surfaceColor = reflectColor * vec3(0.95, 0.9, 0.85);
    out_Col = vec4(surfaceColor, 1.); 
    return; 


  }

  if(dist > 100.0 - EPSILON){
    // not in the shape - color the background    
    vec3 point = u_Eye + marchVals.x * rayDir; // screen space coord
    vec2 st = point.xy / u_Dimensions.xy;     
    vec3 color = vec3(0.0, 0.0, 0.0);    
    color += vec3(0.0, 1.0, 0.0);
    out_Col = vec4(color, 1.0);

    //for starry sky 
    // if (u_TimeOfDay == 1.0) {
    //   //starry sky is u_TimeOfDay = 1.0 
    //     out_Col = getBackgroundColor(st); 
    // } else if (u_TimeOfDay == 2.0) {
    //   //day cycle is u_TimeOfday = 2.0 
    //   out_Col = getMorningColor(rayDir); 
    // }

    out_Col = getBackgroundColor(st); 

    return;
  }

  // lighting
  vec3 normals = getNormals(u_Eye + marchVals.x * rayDir);
   vec3 lightDir = u_Eye; 

  vec3 h = (u_Eye + lightDir) / 2.0; //average view and light vector (view = light vec)

  float specularInt = max(pow(dot(normalize(h), normalize(normals)), 23.0) , 0.0); // specular intensity
  vec3 theColor = vec3(1.0, 0.0, 0.0); 
  float diffuseTerm = dot(normalize(normals), normalize(lightDir)); //dot n and light dir 
  diffuseTerm = clamp(diffuseTerm, 0.0, 1.0); //no negative value s
    
  float ambientTerm = 0.2;
  float lightIntensity = diffuseTerm + ambientTerm;

  vec3 col = getColor(colorVal, lightIntensity, specularInt, u_Eye + marchVals.x * rayDir) * surfaceColor;
  out_Col = vec4(col, 1.0);


}