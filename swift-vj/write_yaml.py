#!/usr/bin/env python3
import os

yaml_content = '''# Launchpad Mini Mk3 Configuration - SYNESTHESIA ONLY
# Controls: Scene selection, presets, meta parameters, global controls

version: 1

colors:
  off: 0
  white: 3
  grey: 1
  red: 5
  redDim: 1
  redBright: 6
  orange: 9
  orangeDim: 7
  yellow: 13
  yellowDim: 11
  yellowBright: 14
  green: 21
  greenDim: 19
  greenBright: 22
  cyan: 37
  cyanDim: 35
  blue: 45
  blueDim: 41
  blueBright: 46
  purple: 53
  purpleDim: 51
  pink: 57
  pinkDim: 55
  magenta: 61

groups:
  favslots:
    type: static
    items:
      - "Favorite 1"
      - "Favorite 2"
      - "Favorite 3"
      - "Favorite 4"
      - "Favorite 5"
      - "Favorite 6"
      - "Favorite 7"
      - "Favorite 8"
  scenes:
    type: dynamic
    source: "$synesthesia/scenes"
  presets:
    type: dynamic
    source: "$synesthesia/presets"
    parent: scenes
  sceneControls:
    type: dynamic
    source: "$synesthesia/controls"
    parent: scenes

global:
  bankButtons:
    - { cc: 91, bank: 0, name: "Meta", idleColor: blue, activeColor: white }
    - { cc: 92, bank: 1, name: "Scenes 1", idleColor: purple, activeColor: white }
    - { cc: 93, bank: 2, name: "Scenes 2", idleColor: purple, activeColor: white }
    - { cc: 94, bank: 3, name: "Scene Ctrl", idleColor: cyan, activeColor: white }
    - { cc: 95, bank: 4, name: "Global", idleColor: green, activeColor: white }
    - { cc: 96, bank: 5, name: "Reserved", idleColor: grey, activeColor: white }
    - { cc: 97, bank: 6, name: "Reserved", idleColor: grey, activeColor: white }
    - { cc: 98, bank: 7, name: "Reserved", idleColor: grey, activeColor: white }
  sceneButtons:
    - { note: 19, function: page, label: "Page 1", idleColor: purpleDim, activeColor: purple }
    - { note: 29, function: page, label: "Page 2", idleColor: purpleDim, activeColor: purple }
    - { note: 39, function: page, label: "Page 3", idleColor: purpleDim, activeColor: purple }
    - { note: 49, function: page, label: "Page 4", idleColor: purpleDim, activeColor: purple }

bank0:
  name: "Meta"
  purpose: "Favorite slots and meta parameters"
  pads:
    - { x: 0, y: 7, mode: selector, group: favslots, index: 0, label: "Fav 1", idleColor: blueDim, activeColor: blue }
    - { x: 1, y: 7, mode: selector, group: favslots, index: 1, label: "Fav 2", idleColor: blueDim, activeColor: blue }
    - { x: 2, y: 7, mode: selector, group: favslots, index: 2, label: "Fav 3", idleColor: blueDim, activeColor: blue }
    - { x: 3, y: 7, mode: selector, group: favslots, index: 3, label: "Fav 4", idleColor: blueDim, activeColor: blue }
    - { x: 4, y: 7, mode: selector, group: favslots, index: 4, label: "Fav 5", idleColor: blueDim, activeColor: blue }
    - { x: 5, y: 7, mode: selector, group: favslots, index: 5, label: "Fav 6", idleColor: blueDim, activeColor: blue }
    - { x: 6, y: 7, mode: selector, group: favslots, index: 6, label: "Fav 7", idleColor: blueDim, activeColor: blue }
    - { x: 7, y: 7, mode: selector, group: favslots, index: 7, label: "Fav 8", idleColor: blueDim, activeColor: blue }
    - { x: 0, y: 6, mode: oneShot, label: "Hue -", idleColor: redDim, activeColor: red, osc: { address: "/controls/meta/hue", args: [-0.1] } }
    - { x: 1, y: 6, mode: oneShot, label: "Hue +", idleColor: redDim, activeColor: red, osc: { address: "/controls/meta/hue", args: [0.1] } }
    - { x: 2, y: 6, mode: oneShot, label: "Sat -", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/meta/saturation", args: [-0.1] } }
    - { x: 3, y: 6, mode: oneShot, label: "Sat +", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/meta/saturation", args: [0.1] } }
    - { x: 4, y: 6, mode: oneShot, label: "Brt -", idleColor: yellowDim, activeColor: yellow, osc: { address: "/controls/meta/brightness", args: [-0.1] } }
    - { x: 5, y: 6, mode: oneShot, label: "Brt +", idleColor: yellowDim, activeColor: yellow, osc: { address: "/controls/meta/brightness", args: [0.1] } }
    - { x: 6, y: 6, mode: oneShot, label: "Speed -", idleColor: greenDim, activeColor: green, osc: { address: "/controls/meta/speed", args: [-0.1] } }
    - { x: 7, y: 6, mode: oneShot, label: "Speed +", idleColor: greenDim, activeColor: green, osc: { address: "/controls/meta/speed", args: [0.1] } }
  programmableRows: [0, 1, 2, 3, 4, 5]

bank1:
  name: "Scenes 1"
  purpose: "Scene selection (0-63)"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]

bank2:
  name: "Scenes 2"
  purpose: "Scene selection (64-127)"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]

bank3:
  name: "Scene Ctrl"
  purpose: "Current scene controls - dynamic"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]

bank4:
  name: "Global"
  purpose: "Global Synesthesia controls"
  pads:
    - { x: 0, y: 7, mode: toggle, label: "Toggle 0", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/0", args: [1.0] }, oscOff: { address: "/controls/global/toggle/0", args: [0.0] } }
    - { x: 1, y: 7, mode: toggle, label: "Toggle 1", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/1", args: [1.0] }, oscOff: { address: "/controls/global/toggle/1", args: [0.0] } }
    - { x: 2, y: 7, mode: toggle, label: "Toggle 2", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/2", args: [1.0] }, oscOff: { address: "/controls/global/toggle/2", args: [0.0] } }
    - { x: 3, y: 7, mode: toggle, label: "Toggle 3", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/3", args: [1.0] }, oscOff: { address: "/controls/global/toggle/3", args: [0.0] } }
    - { x: 4, y: 7, mode: toggle, label: "Toggle 4", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/4", args: [1.0] }, oscOff: { address: "/controls/global/toggle/4", args: [0.0] } }
    - { x: 5, y: 7, mode: toggle, label: "Toggle 5", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/5", args: [1.0] }, oscOff: { address: "/controls/global/toggle/5", args: [0.0] } }
    - { x: 6, y: 7, mode: toggle, label: "Toggle 6", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/6", args: [1.0] }, oscOff: { address: "/controls/global/toggle/6", args: [0.0] } }
    - { x: 7, y: 7, mode: toggle, label: "Toggle 7", idleColor: cyanDim, activeColor: cyan, oscOn: { address: "/controls/global/toggle/7", args: [1.0] }, oscOff: { address: "/controls/global/toggle/7", args: [0.0] } }
    - { x: 0, y: 6, mode: oneShot, label: "Slider 0 -", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/0", args: [-0.1] } }
    - { x: 1, y: 6, mode: oneShot, label: "Slider 0 +", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/0", args: [0.1] } }
    - { x: 2, y: 6, mode: oneShot, label: "Slider 1 -", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/1", args: [-0.1] } }
    - { x: 3, y: 6, mode: oneShot, label: "Slider 1 +", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/1", args: [0.1] } }
    - { x: 4, y: 6, mode: oneShot, label: "Slider 2 -", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/2", args: [-0.1] } }
    - { x: 5, y: 6, mode: oneShot, label: "Slider 2 +", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/2", args: [0.1] } }
    - { x: 6, y: 6, mode: oneShot, label: "Slider 3 -", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/3", args: [-0.1] } }
    - { x: 7, y: 6, mode: oneShot, label: "Slider 3 +", idleColor: greenDim, activeColor: green, osc: { address: "/controls/global/slider/3", args: [0.1] } }
    - { x: 0, y: 5, mode: oneShot, label: "Bang 0", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/0", args: [1.0] } }
    - { x: 1, y: 5, mode: oneShot, label: "Bang 1", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/1", args: [1.0] } }
    - { x: 2, y: 5, mode: oneShot, label: "Bang 2", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/2", args: [1.0] } }
    - { x: 3, y: 5, mode: oneShot, label: "Bang 3", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/3", args: [1.0] } }
    - { x: 4, y: 5, mode: oneShot, label: "Bang 4", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/4", args: [1.0] } }
    - { x: 5, y: 5, mode: oneShot, label: "Bang 5", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/5", args: [1.0] } }
    - { x: 6, y: 5, mode: oneShot, label: "Bang 6", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/6", args: [1.0] } }
    - { x: 7, y: 5, mode: oneShot, label: "Bang 7", idleColor: orangeDim, activeColor: orange, osc: { address: "/controls/global/bang/7", args: [1.0] } }
    - { x: 0, y: 4, mode: oneShot, label: "Knob 0 -", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/0", args: [-0.1] } }
    - { x: 1, y: 4, mode: oneShot, label: "Knob 0 +", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/0", args: [0.1] } }
    - { x: 2, y: 4, mode: oneShot, label: "Knob 1 -", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/1", args: [-0.1] } }
    - { x: 3, y: 4, mode: oneShot, label: "Knob 1 +", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/1", args: [0.1] } }
    - { x: 4, y: 4, mode: oneShot, label: "Knob 2 -", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/2", args: [-0.1] } }
    - { x: 5, y: 4, mode: oneShot, label: "Knob 2 +", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/2", args: [0.1] } }
    - { x: 6, y: 4, mode: oneShot, label: "Knob 3 -", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/3", args: [-0.1] } }
    - { x: 7, y: 4, mode: oneShot, label: "Knob 3 +", idleColor: purpleDim, activeColor: purple, osc: { address: "/controls/global/knob/3", args: [0.1] } }
  programmableRows: [0, 1, 2, 3]

bank5:
  name: "Reserved"
  purpose: "Reserved for future use"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]

bank6:
  name: "Reserved"
  purpose: "Reserved for future use"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]

bank7:
  name: "Reserved"
  purpose: "Reserved for future use"
  pads: []
  programmableRows: [0, 1, 2, 3, 4, 5, 6, 7]
'''

# Get the script directory 
script_dir = os.path.dirname(os.path.abspath(__file__))
yaml_path = os.path.join(script_dir, 'Sources/SwiftVJCore/Resources/launchpad-config.yaml')

# Remove old file if exists
if os.path.exists(yaml_path):
    os.remove(yaml_path)

# Write new file
with open(yaml_path, 'w') as f:
    f.write(yaml_content)
    
print(f'Written {len(yaml_content)} bytes to {yaml_path}')
