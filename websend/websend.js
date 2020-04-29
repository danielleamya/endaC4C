//import { rejects } from "assert";

var users = [];
var userBan_IDs = [];
var samples = [];
var started = false;
let curSamp;
var loaded;
var startTime;
var loadtime;
var biglat;
var big;
var BAN_ID = "c4c-p5tests";
var neo = true;
var connectAttempts;
var client;
var banID = '1001'
var banID2 = '1002'
var banID3 = '1003'
var banID4 = '1004'
var banID5 = '1005'
var c1
var c2
var c3
var c4
var c5
var c6
var streamsNum = 8;
var counts = [streamsNum];
var timer1
var timer2
var updateTimer;
var sampleMode;
var phones;
var updateCheckTimeout;
var updateTime = 7000;
var offlineTime = 12000;
var sampleLoadNum = 0;

var frequency;

var samplebank = 0;
// var stream1_idNum, stream2_idNum, stream3_idNum, stream4_idNum;
// var stream1_IDs, stream2_IDs, stream3_IDs, stream4_IDs;

setup();
//listenToWWSDataWithStomp();
function setup() {
  changeMode(0);
  changeFrequency(0);
  updateCheck();
  phones = {};
  console.log("helloWorld!!!!!")
  //document.getElementById("demo").innerHTML = 5+6;
  //document.write("hello");
  for(i = 0; i<streamsNum; i++){
    counts[i] = 0;
  }
  c1 = 0;
  c2 = 0;
  c3 = 0;
  c4 = 0;
  c5 = 0;
  c6 = 0;
    listenToWWSDataWithStomp();
}

/*
Enables WebMIDI protocol to send triggers via MIDI ports.
Currently looking for MIDI port 2, but should be variable in the future.
*/
function activateSending(){
    WebMidi.enable(function (err) {

        if (err) {
          console.log("WebMidi could not be enabled.", err);
        } else {
            console.log("WebMidi enabled!");



          //Create and append select list
          var selectList = document.createElement("select");
          selectList.id = "mySelect";
          //myParent.appendChild(selectList);

          document.getElementById("midi").append(selectList);
          //Create and append the options
          for (var i = 0; i < WebMidi.inputs.length; i++) {
              var option = document.createElement("option");
              option.value = i.toString();
              option.text = WebMidi.inputs[i].name;
              selectList.appendChild(option);
          }

            //console.log(selElmnt);
            console.log("??");
            console.log(WebMidi.inputs);
            console.log(WebMidi.outputs);
            
        }
        
      });
}

function refreshPorts(){
  var selectList = document.getElementById("mySelect");
  for(var i = 0; i < selectList.children.length; i++){
    selectList.removeChild(selectList.children[i]);
  }
  //Create and append the options
  for (var i = 0; i < WebMidi.inputs.length; i++) {
      var option = document.createElement("option");
      option.value = i.toString();
      option.text = WebMidi.inputs[i].name;
      selectList.appendChild(option);
  }

}

function activatePort(){
  var option = document.getElementById("mySelect").value;
  input = WebMidi.inputs[parseInt(option)];
  console.log("port activated");
  input.addListener('noteon', "all",
      function (e) {
          var note = "" + e.note.name + e.note.octave;
          console.log(e.note.number)
          console.log("Received 'noteon' message (" + e.note.name + e.note.octave + ").");
          sendMIDI(e.note.number)
      }
  );
}

/*
MIDI Input: Currently using MIDI notes C2-D3 (48-62) 
to send triggers to all clients to play their respective samples. 

This was last used for Times Square ICE performance.
But can be adapted for future MIDI use.
*/
function sendMIDI(note){
  console.log("sending midi node " + note);
    switch (note){
        case 1:
          sendTrigger(banID, String(sampleMode) + ' unlooping');
          console.log('C2');
          break;
    
        case 2:
            sendTrigger(banID2, String(sampleMode) + ' unlooping');
          console.log('D2');
          break;
    
        case 3:
          sendTrigger(banID3, String(sampleMode) + ' unlooping');
          console.log('E2');
          break;
    
        case 4:
          sendTrigger(banID4, String(sampleMode) + ' unlooping');
          console.log('F2');
          break;
        case 5:
          console.log('F2');
          break;
        case 55: 
          console.log('G2');
          break;
    
        case 57: 
          console.log('A2');
          break;
    
        case 59:
          console.log('B2');
          break;
    
        case 60:
          console.log('C3');
          break;
      
        case 62:
          console.log('D3');
          break;

        case 65:
            sendTrigger(banID, String(sampleMode) + ' unlooping');
            console.log('G3');
        case 67:
            sendTrigger(banID2, String(sampleMode) + ' unlooping');
            console.log('Bb3');
        case 69:
            sendTrigger(banID3, String(sampleMode) + ' unlooping');
            console.log('D4');
        case 71:
            sendTrigger(banID4, String(sampleMode) + ' unlooping');
            console.log('F4');
    
        default:
          console.log('Pressed key outside of mapped range');
          console.log(note);
      }
}

/*
Parses through keypress events to send triggers to the clients.
	a = Play sample 0 on all clients
	1 = Play sample 1 on all clients
	2 = Switches to allMode (sends sample triggers to all clients)
	3 = Switches to meowMode, 2 individual streams (used in Vault Allure #3 performance)
	4 = Switches to fluteMode, 4 individual streams (used in Vault Allure #3 performance)
	x = Stop all samples from playing
	t = Play test tone (in this case test tone is sample [1])
	n = Update timer variable
*/
document.body.addEventListener("keypress", function(event){
  key = event.which;
  console.log(key);
  if(String.fromCharCode(key)=='a'){
    console.log("setUpdate");

    if(sampleMode!=0&&sampleMode!=3){
      sendTriggers(String(sampleMode) + ' unlooping');
      var d = new Date();
      startTime = d.getTime();
      clearTimeout(updateTimer);
      updateTimer = setTimeout(update, 2000, sampleMode);
    } else if(sampleMode==3){
      sendTriggers(String(sampleMode) + ' ylooping');
      var d = new Date();
      startTime = d.getTime();
      clearTimeout(updateTimer);
      updateTimer = setTimeout(update, 2000, sampleMode);
    }
    else{
      console.log("firsttone");
      clearTimeout(updateTimer);
      startTone(0);
    }
    
  }
  if(String.fromCharCode(key)=='q'){
    console.log("firsttone");
    clearTimeout(updateTimer);
    startTone(0);
  }
    
  else if(String.fromCharCode(key)=='1'){
    changeMode(0);
  }
  else if(String.fromCharCode(key)=='2'){
    changeMode(1);
  }
  else if(String.fromCharCode(key)=='3'){
    changeMode(2);
  }
  else if(String.fromCharCode(key)=='4'){
    changeMode(3);
  }
  else if(String.fromCharCode(key)=='5'){
    changeMode(4);
  }


  else if(String.fromCharCode(key)=='6'){
    changeFrequency(0);
    sendTriggers("frequency0");
  }
  else if(String.fromCharCode(key)=='7'){
    changeFrequency(1);
    sendTriggers("frequency1");
  }
  else if(String.fromCharCode(key)=='8'){
    changeFrequency(2);
    sendTriggers("frequency2");
  }
  else if(String.fromCharCode(key)=='9'){
    changeFrequency(3);
    sendTriggers("frequency3");
  }
  else if(String.fromCharCode(key)=='0'){
    changeFrequency(4);
    sendTriggers("frequency4");
  }


  else if(String.fromCharCode(key)=='x'){
    sendTriggers("stopall");
    clearTimeout(updateTimer);
  }
  else if(String.fromCharCode(key)=='p'){
    sendTriggers("loadall");
  }
  else if(String.fromCharCode(key)=='n'){
    clearTimeout(updateTimer);
  }
  
});

function changeMode(mode){
  sampleMode = mode;
  document.getElementById("mode").innerHTML = "Sample Mode is " + mode;
  sampleLoadNum = mode;
}

function changeFrequency(freq){
  frequency = freq;
  document.getElementById("frequency").innerHTML = "Frequency Mode is " + freq;
  loadFreqNum = freq;
}

function updateCheck(){
  var i = 0;
  for(var phone in phones){
    var d = new Date();
    var value = phones[phone];
    if(d.getTime()>value+offlineTime){
      console.log("Phone " + phone + " is not sending");
      var ID = "phone"+String(i);
      console.log(ID);
      document.getElementById(ID).innerHTML = "Phone " + phone + " is not sending";
    }
    i++;
  }

  updateCheckTimeout = setTimeout(updateCheck, updateTime);
}


/*
 STOMP-based stream listener (no polling)
 Listens to WWS stream for exchange data if connected to an existing stream_no
 Activates sending from webpage to connected clients.
*/
function listenToWWSDataWithStomp() {

//  const url = "ws://stream_bridge_user1:WWS2016@194.137.84.174:15674/ws";
  //const url = "ws://stream_bridge_user1:WWS2016@34.241.186.209:15674/ws";
  //const url = "ws://stream_bridge_user1:WWS2016@135.112.86.21:15674/ws";
  //const url = "ws://stream_bridge_user1:WWS2016@10.12.82.58:5672/ws"
  
  //MH
  //const url = "ws://stream_bridge_user1:WWS2016@10.4.82.58/ws"
  //Paris
  //const url = "ws://stream_bridge_user1:WWS2016@54.154.131.1:15674/ws"
  //EAT
  //const url = "ws://stream_bridge_user1:WWS2016@3.231.148.129:15674/ws"

  // WSS
  const url = "wss://stream_bridge_user1:WWS2016@wws_us_east1.msv-project.com/ws";

  const exchange = "/exchange/data/";

  // Check if we have a BAN_ID provided as an URL parameter




  client = Stomp.client(url);

  function onError() {
    console.log('Stomp error');
    connectAttempts++;
    if(connectAttempts>4){

    } else{
      listenToWWSDataWithStomp();
    }
  }

  function onConnectListener(x) {
        console.log("Listening to " + BAN_ID)
        activateSending();

    //client.subscribe(exchange+BAN_ID+".motion.sleeve", function(msg) {
    client.subscribe(exchange+BAN_ID, function(msg) {
      // Update motion information
      //console.log(msg.body);
      let data = JSON.parse(msg.body);
      parseReceived(data);
      curSamp = data.code;
      //console.log(data.code);

      //Latency display
      /*
      clear();
      var d = new Date();
      console.log(d.getTime() - data.time);
      var lat = d.getTime() - data.time;
      if(lat>biglat){
        biglat = lat;
      }
      */
      //text('Latency:  ' + lat, 100, 170);
      //text('Loaded Time:  ' + loadtime, 100, 270);
      //text('Top Lat:  ' + biglat, 100, 370);

    });
  }

  client.connect("stream_bridge_user1", "WWS2016", onConnectListener, onError, "/test");
}


/*
When a client has fully buffered the sample bank onto their device,
server webpage displays debug message to inform the user for each tag. 
*/
function parseReceived(data){
  console.log(data);
  console.log(data.code)
  if(String(data.code).includes("fully loaded")){
    var userID = data.code.split(" ");
    var k = parseInt(String(data.code));
    console.log("parsed is " + k);
    if(k!=NaN){
        counts[k-1001] = counts[k-1001]+1;
        console.log("updated phone label to " + k);
        document.getElementById(String(k)).innerHTML = "phone " + String(k-1000) + " loaded ID: " + userID[1] + ", total on stream: " + String(counts[k-1001]);
    }
  }
  if(String(data.code).includes("online")){
    var userID = data.code.split(" ");
    //Populates dictionary
    var d = new Date();
    phones[userID[1]] = d.getTime();
    sendTriggers(String(sampleLoadNum)+ " load");

    //Populates array
    var i;
    for (i = 0; i < users.length; i++){
      if (userID[1] == users[i]){
        console.log("Generating new name...");
      }
    } 
    users.push(userID[1]);
    console.log(users);
  }
  else if(String(data.code).includes("still")){
    var userID = data.code.split(" ");
    console.log(userID);
    var d = new Date();
    phones[userID[1]] = d.getTime();
    console.log("Updated phone " + userID[1] + " to " + d.getTime());
  }
}

function sendTime(samp){
  payload = sampleLoadNum + " time" + String(document.getElementById("timeSend").value);
  sendTriggers(payload);
}

/*
Actives debug console on the sender/server webpage
Shows current mode and status of sample loading on clients with tags 1001-1006.
*/
function debugMode(){
	var debugMode = document.getElementById("debug").checked;
  if (debugMode){
    document.getElementById("mode").style.display = "block";
    document.getElementById("frequency").style.display = "block";
    for(i = 1001; i<1006;i++){
      document.getElementById(String(i)).style.display = "block";
    }
    for(i = 0; i<500; i++){
      element = "phone" + String(i);
      document.getElementById(element).style.display = "block";
    }
  } else {
    document.getElementById("mode").style.display = "none";
    document.getElementById("frequency").style.display = "none";
    for(i = 1001; i<1006;i++){
      console.log("i is " + String(i));
      document.getElementById(String(i)).style.display = "none";
    }
    for(i = 0; i<500; i++){
      element = "phone" + String(i);
      document.getElementById(element).style.display = "none";
    }
  }
	// console.log(debugMode);
}

function genName(tag){
  var name = String(tag);
  let r = Math.random().toString(36).substring(7);
  name = name + " " + String(r);
  return name;
}

function update(samp){
  console.log("update!");
  var d = new Date();
  payload = samp + " update " + String(d.getTime()-startTime);
  sendTriggers(payload);
  updateTimer = setTimeout(update, 1000, samp);
}

function startTone(samp){
  console.log("playing start tone")
  payload = samp + " unlooping rand";
  sendTriggers(payload);
  updateTimer = setTimeout(startTone, 5000, samp);
}

/*
Multi-sending function that can send triggers to multiple ban IDs at once.
	allMode = send triggers simultaneously to all clients to play sample_no N
	meowMode = send triggers simultaneously to clients on streams 1001 and 1002
	fluteMode = send triggers simultaneously to clients on streams 1003 - 1006
*/
function sendTriggers(samp){
    sendTrigger(banID, samp)
    sendTrigger(banID2, samp)
    sendTrigger(banID3, samp)
    sendTrigger(banID4, samp)
    sendTrigger(banID5, samp)
    //sendTrigger(banID6, samp)
    //sendTrigger(banID7, samp)
    //sendTrigger(banID8, samp)
}

/*
Sends data to WWS to play sample based on ban ID & sample_no.
*/
function sendTrigger(ban, samp) {
	if (client) {		
		let payload = {
			code: samp
		}

        client.send("/exchange/data/" + ban, {}, JSON.stringify(payload));
        console.log("sent " + JSON.stringify(payload));
        //document.getElementById("lastsent").innerHTML = 5+6;
        //document.write("sent " + JSON.stringify(payload));
	}
}



