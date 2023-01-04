/**
  Copyright (C) 2012-2020 by Autodesk, Inc.
  All rights reserved.

  Custum Post Processor for Duet 3  based on :
    - RepRap post processor configuration.
    - ULTIMATERepRapPost
    - Workbee

  $Program: JenkinsCNCRepRap
  $Version: 010
  $Date: 2022-12-25 10:00:53 $
  
  FORKID {996580A5-D617-4b85-9DA2-C4EF3CBF92FC}
*/

/**
  OBJECTIVE:
    -This file is a postprocessor for Fusion 360 that will output functional Gcode for a Duet 3
    -I want the minimum of settings within the post processor , more complex tasks should be done by gcode on the duet3
    - tasks are executed by macros. Macros will be specified on the Duet board
    - keeping extra gcode logic on the duet allows for easier user customization and  allows work arounds to use gcode not supported by the duet (such as coolent/M7,M9) 
  Post Processor
    - Output G code / Mode
    - Identify tool changes
    - call macros
  Duet
    - Automated tool chage macro
    - Manual tool change macro
    - turn on/off accessories like dust colletors, coolent, etc with-in called macros
*/

/**
  Common Gcode Used reference list
  G0 - Rapid Move 
  G1 - Linear Move
  G2/3  - Arc Move
  G4 - Dwell
  G20- Set to inches
  G21 - Set to mm
  G28 - Home
  G90 - absolute positioning
  G91- relative positioning

  M0 - Stop
  M1 - Optinal Stop
  M2 - Program End   // Not supported
  M3 - Spindle ON
  M5 - Spindle Off
  M7 - Coolent on  // not supported on duet
  M9 - Coolent Off // not supported in duet 

  M98- Call Macro/Subprogram      M98 P"mymacro.g"
  M577 - Wait untill IO is triggered

  T# - Tool number
*/

//--------------------------- Post Processor Description ----------------------------------------//

description = "JenkinsCNCRepRap";
longDescription = " Custum Post Processor for Duet 3 REPRAP";
vendor = "Jenkins Robotics";
vendorUrl = "http://reprap.org";
legal = "Copyright (C) 2012-2020 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 40783;
extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // allow any circular motion


//--------------------------- User Defined Properties ----------------------------------------//

// This section defines the Post Processor user interface's variables and layout

properties = {
  //section 1- Formats
  writeMachine: {       //goood
    title      : "Write machine",
    description: "Output the machine settings in the header of the code.",
    group      : "1- Formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  writeTools: {   //good
    title      : "Write tool list",
    description: "Output a tool list in the header of the code.",
    group      : "1- Formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  writeVersion: {       // Needs to be be added
    title      : "Write version",
    description: "Write the version number in the header of the code.",
    group      : "1- Formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  showSequenceNumbers: {      // Need to check 
    title      : "Use sequence numbers",
    description: "'Yes' outputs sequence numbers on each block, 'Only on tool change' outputs sequence numbers on tool change blocks only, and 'No' disables the output of sequence numbers.",
    group      : "1- Formats",
    type       : "enum",
    values     : [
      {title:"Yes", id:"true"},
      {title:"No", id:"false"},
      {title:"Only on tool change", id:"toolChange"}
    ],
    value: "toolChange",
    scope: "post"
  },
  sequenceNumberStart: {    //good
    title      : "Start sequence number",
    description: "The number at which to start the sequence numbers.",
    group      : "1- Formats",
    type       : "integer",
    value      : 10,
    scope      : "post"
  },
  sequenceNumberIncrement: {        //good
    title      : "Sequence number increment",
    description: "The amount by which the sequence number is incremented by in each block.",
    group      : "1- Formats",
    type       : "integer",
    value      : 5,
    scope      : "post"
  },
  separateWordsWithSpace: {  //good
    title      : "Separate words with space",
    description: "Adds spaces between words if 'yes' is selected.",
    group      : "1- Formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },

  // Section 2- Tools
  autoToolChange: {
    title: "Automated tool change ",
    description: "Enable automatic tool change. Program will automaticly change tool and continue program. (Uses Duet3 built in tool managment macros Tpre/Tpost/Tfree)",
    group: "2- Tools",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },  
  manualToolChange: {
    title: "Manual tool change - Call user macro ",
    description: "Asks for manual tool change. Program is interrupted until tool change is confirmed.  (Uses M98 .. User macro file name must match 'ManualToolChange.g').",
    group: "2- Tools",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },  
  probeToolOnChange: {
    title: "Probe tool on tool change - Call user macro",
    description: "Call tool probe subprogram. Creates Probe routine after each tool change (Uses M98 .. User macro file name must match 'ToolZProbe.g')",
    group: "2- Tools",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  homeOnToolChange: {
    title: "Home axis on tool change",
    description: "Homes all axis after tool is changed and before it is potentailly probed.)",
    group: "2- Tools",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },

  // Sectuion 3- Spindle
  spindleMode: {            //good
    title: "Enable spindle gcode",
    description: "Specify Desired Spindle Gcode",
    group: "3- Spindle",
    type: "enum",
    values:  [
      { title: "No Spindle Mcode ", id: "nospindle" },    // Mcode not needed for manual ON/OFF spindles--- But Mcode should be writen for good Gcode readablility
      { title: "Spindle On/Off", id: "spindlestate" },       // M3 and M5 only
      { title: "Spindle RPM", id: "spindlerpm" }           // M3 SXXX and M5 SXXXX 
    ],
    value: "spindlerpm",
    scope      : "post"
  },
  dwellMethod: {    // good
    title: "Enable spindle dwell",
    description: "Specify Desired Dwell Method. Dwell allocates time for spindle to reach operating speed",
    group: "3- Spindle",
    type: "enum",
    values:  [
      { title: "No dwell - Not Recommended", id: "nodwell" },
      { title: "Use Time", id: "dwelltime" },     // G4   Gcode wait (false)
      { title: "Use IO", id: "dwellio" }        // M577   Gcode Wait for trigger + 1 Second(true)
    ],
    value: "dwellio",
    scope      : "post"
  },
  dwellInSeconds: {               //Good
    title      : "Dwell in seconds (Keep checked)",
    description: "Specifies the unit for dwelling, set to 'Yes' for seconds and 'No' for milliseconds.",
    group      : "3- Spindle",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  dwellTime: {            // good
    title      : "Dwell time amount (Dwell time only)",
    description: "The dwell time desired (seconds or milliseconds) ",
    group      : "3- Spindle",
    type       : "integer",
    value      : 5,
    scope      : "post"
  },
  dwellPNumber: {          // good   
    title      : "Dwell input pin (Dwell IO only)",
    description: "The Pnnn Input pin that the program will wait for. [M577 P1 Spindle On] (Low = Spindle is not on -- Wait / High = Spindle is On -- Continue) ",    // Gcode used M577 [Input config  M950 J2] --->[Gcode M577 P2]
    group      : "3- Spindle",
    type       : "integer",
    value      : 1,
    scope      : "post"
  },

 
  // 4- General
  safePositionMethod: {   //good
    title      : "Safe Retracts",
    description: "Select your desired retract option. 'Clearance Height' retracts to the operation clearance height.",
    group      : "4- General",
    type       : "enum",
    values     : [
      {title:"G28", id:"G28"},
      // {title: "G53", id: "G53"},
      {title:"Clearance Height", id:"clearanceHeight"}
    ],
    value: "G28",
    scope: "post"
  },
  beepOn: {             
    title      : "Audible signal when operator's attention needed",
    description: "Makes a beep when attention required",
    group      : "4- General",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  cautioncomment: {             //good
    title      : "Display a caution comment at startup",
    description: "Displays a caution comment that required the user to dismiss the message before program begins cutting.",
    group      : "4- General",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  mmOnly: {             // good
    title      : "MM only, Prevent the use of INCHES",
    description: "CNC machine seems to perform better in inches. This setting prevents the execution of program in inches and notifies user to change setting to milimeter.",
    group      : "4- General",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },

  // Section 5- Unsupported or Untested
  optionalStop: {   //good
    title      : "Optional stop",
    description: "Outputs optional stop code during when necessary in the code.",
    group      : "5- Unsupported or Future Development",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  allowArcs: {    //good
    title      : "Allow arcs",
    description: "If disabled, all arcs will be linearized.",
    group      : "5- Unsupported or Future Development",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  useCoolent: {            
    title      : "Use Coolent",
    description: "Duet doent support coolent at time of release. Enable / Disable M7 and M9 output for coolent/dust collector.", 
    group      : "5- Unsupported or Future Development",
    type       : "boolean",
    value      : false,         // RepRap does not directly support dust collector via M7 / M9.... Work around, use macros on the duet 3 to turn on/off output during tool change / probing etc... 
    scope      : "post"
  },
  preloadTool: {    //good
    title      : "Preload tool",
    description: "Preloads the next tool at a tool change (if any).",
    group      : "5- Unsupported or Future Development",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
};

//--------------------------- User Defined Properties ----------------------------------------//

// wcs definiton
wcsDefinitions = {
  useZeroOffset: false,
  wcs          : [
    {name:"Standard", format:"#", range:[1, 1]}
  ]
};

//--------------------------- Variables ----------------------------------------//

var numberOfToolSlots = 9999;

var singleLineCoolant = false; // specifies to output multiple coolant codes in one line rather than in separate lines
// samples:
// {id: COOLANT_THROUGH_TOOL, on: 88, off: 89}
// {id: COOLANT_THROUGH_TOOL, on: [8, 88], off: [9, 89]}
// {id: COOLANT_THROUGH_TOOL, on: "M88 P3 (myComment)", off: "M89"}
var coolants = [
  {id: COOLANT_FLOOD, on: 8},
  {id: COOLANT_MIST, on: 7},
  {id: COOLANT_THROUGH_TOOL},
  {id: COOLANT_AIR},
  {id: COOLANT_AIR_THROUGH_TOOL},
  {id: COOLANT_SUCTION},
  {id: COOLANT_FLOOD_MIST},
  {id: COOLANT_FLOOD_THROUGH_TOOL},
  {id: COOLANT_OFF, off: 9}
];

var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var milliFormat = createFormat({decimals:0}); // milliseconds
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({onchange:function () {retracted = false;}, prefix:"Z"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);

// circular output
var iOutput = createVariable({prefix:"I", force:true}, xyzFormat);
var jOutput = createVariable({prefix:"J", force:true}, xyzFormat);
var kOutput = createVariable({prefix:"K", force:true}, xyzFormat);

var gMotionModal = createModal({force:true}, gFormat); // modal group 1 // G0-G1, ...
var gPlaneModal = createModal({ onchange: function () { gMotionModal.reset(); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var forceSpindleSpeed = false;
var currentWorkOffset;
var retracted = false; // specifies that the tool has been retracted to the safe plane

//--------------------------- Functions ----------------------------------------//
//  function with "ON" is a main function that will call subfunctions and responsible majority of format (on###### )


/**
  Writes the "Sequence Number" block. -- N##    // Outputs on each line if true
*/
function writeBlock() {
  if (!formatWords(arguments)) {
    return;
  }
  if (getProperty("showSequenceNumbers") == "true") {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += getProperty("sequenceNumberIncrement");
  } else {
    writeWords(arguments);
  }
}

/**
  function that formats text
*/
function formatComment(text) {
  return "(" + String(text).replace(/[()]/g, "") + ")";
}

/**
  Writes the Tool Code block - used for tool changes only. 
*/
function writeToolBlock() {
  var show = getProperty("showSequenceNumbers");
  setProperty("showSequenceNumbers", (show == "true" || show == "toolChange") ? "true" : "false");
  writeBlock(arguments);
  setProperty("showSequenceNumbers", show);
}

/**
  Call this function to Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}

/**
  Main Function - Execute on start 
*/
function onOpen() {
  if (!getProperty("separateWordsWithSpace")) {
    setWordSeparator("");
  }
  // Get the Starting Sequence Number from user defined properties
  sequenceNumber = getProperty("sequenceNumberStart");
  
  // Write custom comment 
  writeComment(" Made With JenkinsCNCRepRap Post Processor ");               
  writeComment(" Support Us @ https://www.patreon.com/JenkinsRobotics");    
  writeComment("---------------------------------------------------------");
 
  
  // Write Program Name 
  if (programName) {         
    writeComment(programName);
  }
  // Write Program comment
  if (programComment) {     
    writeComment(programComment);
  }

  // Write version configuration comment
  if (getProperty("writeVersion")) {
    writeComment(localize("Post-Processor Information:"));
    writeComment(localize("   post name: JenkinsCNCreprap"));
    if ((typeof getHeaderVersion == "function") && getHeaderVersion()) {
      writeComment(localize("   post version") + ": " + getHeaderVersion());
    }
    if ((typeof getHeaderDate == "function") && getHeaderDate()) {
      writeComment(localize("   post modified") + ": " + getHeaderDate().replace(/:/g, "-"));
    }
    writeComment("   post info: Generated for RepRap firmware 3.x running on Duet3D controller that works in CNC mode")
  }

  // Write machine configuration comment
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();
  if (getProperty("writeMachine") && (vendor || model || description)) {
    writeComment(localize("Machine Information:"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // Write tool information Comment
  if (getProperty("writeTools")) {
    writeComment(localize("Tool Information:"));
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }
    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }

  // print caution message
  if (getProperty("cautioncomment")) {
    bCautious();
  }

  // Write absolute coordinates
  writeBlock(gAbsIncModal.format(90));
  // Enable Arcs
  if (getProperty("allowArcs")) {
    writeBlock(gPlaneModal.format(17));             // NOT IN OLD
  }

  // Set program units
  switch (unit) {
  case IN:
    if (getProperty("mmOnly")) {
      error(localize("Please select millimeters as unit when post processing. Inch mode is not recommended by the JenkinsRobotics team."));
      return;
    } else  {
      writeBlock(gUnitModal.format(20));
      break;
    }
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }

  // dust collector is not in use. If got a controlled one, uncomment below
  if (getProperty("useCoolent")) {
    writeBlock(mFormat.format(7)); // turns on dust collector
  }

}



/**
  Main Function - Execute on comments 
*/
function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function isProbeOperation() {
  return (hasParameter("operation-strategy") &&
    getParameter("operation-strategy") == "probe");
}

/**
  Main Function - Execute on sections 
*/
function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis()) ||
    (currentSection.isOptimizedForMachine() && getPreviousSection().isOptimizedForMachine() &&
      Vector.diff(getPreviousSection().getFinalToolAxisABC(), currentSection.getInitialToolAxisABC()).length > 1e-4) ||
    (!machineConfiguration.isMultiAxisConfiguration() && currentSection.isMultiAxis()) ||
    (!getPreviousSection().isMultiAxis() && currentSection.isMultiAxis() ||
      getPreviousSection().isMultiAxis() && !currentSection.isMultiAxis()); // force newWorkPlane between indexing and simultaneous operations
  if (insertToolCall || newWorkOffset || newWorkPlane) {
    
    // stop spindle before retract during tool change
    if (insertToolCall && !isFirstSection()) {
      onCommand(COMMAND_STOP_SPINDLE);
    }

    // retract to safe plane
    writeRetract(Z);
    zOutput.reset();
  }

  writeln("");
  
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    // Coolent and Dust collector are different not same mcodes
    if (getProperty("useCoolent")) {              
      setCoolant(COOLANT_OFF);
    }
    // Optional Stop
    if (!isFirstSection() && getProperty("optionalStop")) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > numberOfToolSlots) {
      warning(localize("Tool number exceeds maximum value."));
    }

     // Output New Tool Number -- Duet performes AutoToolChange
    if (getProperty("autoToolChange")) {
      writeComment("---- Perform Tool Change ----");
      writeToolBlock("T" + toolFormat.format(tool.number));
    }

     // If manual tool change is selected
    if (getProperty("manualToolChange")) {
      writeComment("---- Perform Manual Tool Change ----");
      // write New tool comment
      writeComment("T" + toolFormat.format(tool.number));       
      // "N" block
      writeToolBlock(" " );
      // Beep for operator
      if (getProperty("beepOn")) {
        writeBlock("M300");
      }
      // Operator Tool Change Comment
      writeBlock(mFormat.format(291) + " P\" Insert Tool " + toolFormat.format(tool.number) + ". Exercise extreme caution while changing tool.\" R\"CAUTION!\" S2");
      // Call Macro/Subprogram  --  M98 P"mymacro.g"
      writeBlock(mFormat.format(98) + " P\"ManualToolChange.g\""); //ToolZProbe.g
    }

     // this is not needed because we do sophisticated probing
    if (getProperty("homeOnToolChange") == true) {
      writeBlock(gFormat.format(28));
    }
    

     // this is not needed because we do sophisticated probing
    if (getProperty("probeToolOnChange") == true) {
      writeBlock(mFormat.format(98) + " P\"ToolZProbe.g\""); //ToolZProbe.g
    }


    // tool comment (reprap)
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }

    if (getProperty("preloadTool")) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        writeBlock("T" + toolFormat.format(nextTool.number));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstToolNumber = section.getTool().number;
        if (tool.number != firstToolNumber) {
          writeBlock("T" + toolFormat.format(firstToolNumber));
        }
      }
    }
  }
  


  // Spindle output
  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(spindleSpeed, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {

    if (spindleSpeed < 1) {
      error(localize("Spindle speed out of range."));
    }
    if (spindleSpeed > 99999) {
      warning(localize("Spindle speed exceeds maximum value."));
    }

    // print Spindle ON/OFF 
    if (getProperty("spindleMode") == "spindlestate") {                                          
      writeBlock( mFormat.format(tool.clockwise ? 3 : 4)  ); 
    }
    // print Spindle With RPM 
    if (getProperty("spindleMode") == "spindlerpm") {                                           
      writeBlock( mFormat.format(tool.clockwise ? 3 : 4), sOutput.format(spindleSpeed)   ); 
    }

    // print dwell IO
    if (getProperty("dwellMethod") == "dwellio") {                                           
      writeBlock(mFormat.format(577), "P" + getProperty("dwellPNumber"));   // use dwell io
      writeBlock(gFormat.format(4), "S1" );    // use dwell for 1 second
    } 
    // print dwell Time
    if (getProperty("dwellMethod") == "dwelltime") {                                           
      writeBlock(gFormat.format(4), "S" + getProperty("dwellTime"));    // use dwell time
    }
  }

  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset != 0) {
    warningOnce(localize("Work offset is not supported."), WARNING_WORK_OFFSET);
  }

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  // set coolant          M7/M9 COOLLANT 
  if (getProperty("useCoolent")) {
    setCoolant(tool.coolant);
  }

  forceAny();
  // Enable Arcs
  if (getProperty("allowArcs")) {
    writeBlock(gPlaneModal.format(17));             // NOT IN OLD
  }




  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    }
  }

  if (insertToolCall || retracted) {
    gMotionModal.reset();
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
    );
    writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
  } else {
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0),
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y)
    );
  }
}

/**
  Main Function - For Dwell blocks 
*/
function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  // seconds to milliseconds -- G4 uses milliseconds
  milliseconds = clamp(1, seconds * 1000, 99999);
  writeBlock(gFormat.format(4), "P" + milliFormat.format(milliseconds));
}

/**
  Main Function - Spindle  Blocks
*/
function onSpindleSpeed(spindleSpeed) {
  // print Spindle ON/OFF 
  if (getProperty("spindleMode") == "spindlestate") {                                          
    writeBlock( mFormat.format(tool.clockwise ? 3 : 4)  ); 
  }
  // print Spindle With RPM 
  if (getProperty("spindleMode") == "spindlerpm") {                                           
    writeBlock( mFormat.format(tool.clockwise ? 3 : 4), sOutput.format(spindleSpeed)   ); 
  }

  // print dwell IO
  if (getProperty("dwellMethod") == "dwellio") {                                           
    writeBlock(mFormat.format(577), "P" + getProperty("dwellPNumber"));   // use dwell io
    writeBlock(gFormat.format(4), "S1" );    // use dwell for 1 second
  } 
  // print dwell Time
  if (getProperty("dwellMethod") == "dwelltime") {                                           
    writeBlock(gFormat.format(4), "S" + getProperty("dwellTime"));    // use dwell time (seconds)
  }



  var method = getProperty("safePositionMethod");
  if (method == "clearanceHeight") {
    if (!is3D()) {
      error(localize("Retract option 'Clearance Height' is not supported for multi-axis machining."));
    }
    return;
  }



  
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode is not supported."));
      return;
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (isHelical()) {
    linearize(tolerance);
    return;
  }

  if (!getProperty("allowArcs")) {
    linearize(tolerance);
    return;
  }

  var start = getCurrentPosition();

  gMotionModal.reset();

  switch (getCircularPlane()) {
  case PLANE_XY:
    writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x), jOutput.format(cy - start.y), feedOutput.format(feed));
    break;
  case PLANE_ZX:
    writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x), kOutput.format(cz - start.z), feedOutput.format(feed));
    break;
  case PLANE_YZ:
    writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y), kOutput.format(cz - start.z), feedOutput.format(feed));
    break;
  default:
    linearize(tolerance);
  }
}

var currentCoolantMode = COOLANT_OFF;
var coolantOff = undefined;
var forceCoolant = false;

function setCoolant(coolant) {
  var coolantCodes = getCoolantCodes(coolant);
  if (Array.isArray(coolantCodes)) {
    if (singleLineCoolant) {
      writeBlock(coolantCodes.join(getWordSeparator()));
    } else {
      for (var c in coolantCodes) {
        writeBlock(coolantCodes[c]);
      }
    }
    return undefined;
  }
  return coolantCodes;
}

function getCoolantCodes(coolant) {
  var multipleCoolantBlocks = new Array(); // create a formatted array to be passed into the outputted line
  if (!coolants) {
    error(localize("Coolants have not been defined."));
  }
  if (isProbeOperation()) { // avoid coolant output for probing
    coolant = COOLANT_OFF;
  }
  if (coolant == currentCoolantMode) {
    return undefined; // coolant is already active
  }
  if ((coolant != COOLANT_OFF) && (currentCoolantMode != COOLANT_OFF) && (coolantOff != undefined)) {
    if (Array.isArray(coolantOff)) {
      for (var i in coolantOff) {
        multipleCoolantBlocks.push(mFormat.format(coolantOff[i]));
      }
    } else {
      multipleCoolantBlocks.push(mFormat.format(coolantOff));
    }
  }

  var m;
  var coolantCodes = {};
  for (var c in coolants) { // find required coolant codes into the coolants array
    if (coolants[c].id == coolant) {
      coolantCodes.on = coolants[c].on;
      if (coolants[c].off != undefined) {
        coolantCodes.off = coolants[c].off;
        break;
      } else {
        for (var i in coolants) {
          if (coolants[i].id == COOLANT_OFF) {
            coolantCodes.off = coolants[i].off;
            break;
          }
        }
      }
    }
  }
  if (coolant == COOLANT_OFF) {
    m = !coolantOff ? coolantCodes.off : coolantOff; // use the default coolant off command when an 'off' value is not specified
  } else {
    coolantOff = coolantCodes.off;
    m = coolantCodes.on;
  }

  if (!m) {
    onUnsupportedCoolant(coolant);
    m = 9;
  } else {
    if (Array.isArray(m)) {
      for (var i in m) {
        multipleCoolantBlocks.push(mFormat.format(m[i]));
      }
    } else {
      multipleCoolantBlocks.push(mFormat.format(m));
    }
    currentCoolantMode = coolant;
    return multipleCoolantBlocks; // return the single formatted coolant value
  }
  return undefined;
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_SPINDLE_COUNTERCLOCKWISE:4,
  COMMAND_STOP_SPINDLE:5
};

function onCommand(command) {
  switch (command) {
  case COMMAND_STOP:
    writeBlock(mFormat.format(0));
    forceSpindleSpeed = true;
    forceCoolant = true;
    return;
  case COMMAND_OPTIONAL_STOP:
    writeBlock(mFormat.format(1));
    forceSpindleSpeed = true;
    forceCoolant = true;
    return;
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  // Enable Arcs
  if (getProperty("allowArcs")) {
    writeBlock(gPlaneModal.format(17));             // NOT IN OLD
  }
  if (!isLastSection() && (getNextSection().getTool().coolant != tool.coolant)) {
    setCoolant(COOLANT_OFF);
  }
  forceAny();
}

/** Output block to do safe retract and/or move to home position. */
function writeRetract() {
  var words = []; // store all retracted axes in an array
  var retractAxes = new Array(false, false, false);
  var method = getProperty("safePositionMethod");
  if (method == "clearanceHeight") {
    if (!is3D()) {
      error(localize("Retract option 'Clearance Height' is not supported for multi-axis machining."));
    }
    return;
  }
  validate(arguments.length != 0, "No axis specified for writeRetract().");

  for (i in arguments) {
    retractAxes[arguments[i]] = true;
  }
  if ((retractAxes[0] || retractAxes[1]) && !retracted) { // retract Z first before moving to X/Y home
    error(localize("Retracting in X/Y is not possible without being retracted in Z."));
    return;
  }
  // special conditions
  /*
  if (retractAxes[2]) { // Z doesn't use G53
    method = "G28";
  }
  */

  // define home positions
  var _xHome;
  var _yHome;
  var _zHome;
  if (method == "G28") {
    _xHome = toPreciseUnit(0, MM);
    _yHome = toPreciseUnit(0, MM);
    _zHome = toPreciseUnit(0, MM);
  } else {
    _xHome = machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : toPreciseUnit(0, MM);
    _yHome = machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : toPreciseUnit(0, MM);
    _zHome = machineConfiguration.getRetractPlane() != 0 ? machineConfiguration.getRetractPlane() : toPreciseUnit(0, MM);
  }
  for (var i = 0; i < arguments.length; ++i) {
    switch (arguments[i]) {
    case X:
      words.push("X" + xyzFormat.format(_xHome));
      xOutput.reset();
      break;
    case Y:
      words.push("Y" + xyzFormat.format(_yHome));
      yOutput.reset();
      break;
    case Z:
      words.push("Z" + xyzFormat.format(_zHome));
      zOutput.reset();
      retracted = true;
      break;
    default:
      error(localize("Unsupported axis specified for writeRetract()."));
      return;
    }
  }
  if (words.length > 0) {
    switch (method) {
    case "G28":
      gMotionModal.reset();
      gAbsIncModal.reset();
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), words);
      writeBlock(gAbsIncModal.format(90));
      break;
    case "G53":
      gMotionModal.reset();
      writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), words);
      break;
    default:
      error(localize("Unsupported safe position method."));
      return;
    }
  }
}

function onClose() {
  // Coolent and Dust collector Off
  if (getProperty("useCoolent")) {              
    setCoolant(COOLANT_OFF);
    writeBlock(mFormat.format(9)); // turns off dust collector
  }
  // Home Z
  writeRetract(Z);
  // Home X, Y
  writeRetract(X, Y);
  // Spindle stop
  writeBlock(mFormat.format(5)); 
  // Stop program
  writeBlock(mFormat.format(0)); 
}


//--------------------------- Custom  Functions ----------------------------------------//

/*
start up warining function 
 */
function bCautious() {
  if (getProperty("beepOn")) {
    writeBlock("M300");
  }
  writeBlock(mFormat.format(291) + " P\"SAFETY FIRST! Ensure Tools are ready, Pneumatics are on and work piece is secure. Exercise extreme caution while machining.\" R\"CAUTION!\" S2");
  return;
}


function setProperty(property, value) {
  properties[property].current = value;
}



