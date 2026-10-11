{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 9,
      "minor": 0,
      "revision": 7,
      "architecture": "x64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [
      100,
      100,
      1200,
      1100
    ],
    "openrect": [
      0,
      0,
      600,
      169
    ],
    "default_fontsize": 10.0,
    "default_fontname": "Arial Bold",
    "gridsize": [
      8.0,
      8.0
    ],
    "boxanimatetime": 500,
    "boxes": [
      {
        "box": {
          "id": "title",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            20,
            40,
            150,
            22
          ],
          "text": "ORIGINAL SONG - TAP / HOLD",
          "presentation": 1,
          "presentation_rect": [
            10,
            4,
            550,
            20
          ]
        }
      },
      {
        "box": {
          "id": "hint",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            180,
            40,
            150,
            22
          ],
          "text": "Tap = your hit. Hold = join the original rhythm at its current position.",
          "presentation": 1,
          "presentation_rect": [
            10,
            27,
            580,
            20
          ]
        }
      },
      {
        "box": {
          "id": "hint2",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            340,
            40,
            150,
            22
          ],
          "text": "Play the song. Release stops. Source: SONG RHYTHMS track.",
          "presentation": 1,
          "presentation_rect": [
            10,
            49,
            570,
            20
          ]
        }
      },
      {
        "box": {
          "id": "stop",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            500,
            40,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            460,
            140,
            20,
            20
          ]
        }
      },
      {
        "box": {
          "id": "stoplabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            660,
            40,
            150,
            22
          ],
          "text": "Release all",
          "presentation": 1,
          "presentation_rect": [
            485,
            140,
            100,
            20
          ]
        }
      },
      {
        "box": {
          "id": "zero",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            40,
            150,
            22
          ],
          "text": "0"
        }
      },
      {
        "box": {
          "id": "notes",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            980,
            40,
            150,
            22
          ],
          "text": "notein"
        }
      },
      {
        "box": {
          "id": "pair",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            75,
            150,
            22
          ],
          "text": "pack 0 0"
        }
      },
      {
        "box": {
          "id": "route",
          "maxclass": "newobj",
          "numinlets": 7,
          "numoutlets": 7,
          "patching_rect": [
            180,
            75,
            150,
            22
          ],
          "text": "route 36 38 42 37 56 45"
        }
      },
      {
        "box": {
          "id": "p1label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            340,
            75,
            150,
            22
          ],
          "text": "CC1 Kick",
          "presentation": 1,
          "presentation_rect": [
            10,
            76,
            130,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p1hit",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            500,
            75,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            10,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p1hold",
          "maxclass": "toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            660,
            75,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            48,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p1heldlabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            820,
            75,
            150,
            22
          ],
          "text": "Follow",
          "presentation": 1,
          "presentation_rect": [
            74,
            103,
            66,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p1raw",
          "maxclass": "number",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            980,
            75,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            10,
            136,
            45,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p1cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            20,
            110,
            150,
            22
          ],
          "text": "ctlin 1"
        }
      },
      {
        "box": {
          "id": "p1gt",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            110,
            150,
            22
          ],
          "text": "> 0"
        }
      },
      {
        "box": {
          "id": "p1edge",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            340,
            110,
            150,
            22
          ],
          "text": "change"
        }
      },
      {
        "box": {
          "id": "p1sel",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 3,
          "patching_rect": [
            500,
            110,
            150,
            22
          ],
          "text": "sel 1 0"
        }
      },
      {
        "box": {
          "id": "p1down",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            660,
            110,
            150,
            22
          ],
          "text": "t b b"
        }
      },
      {
        "box": {
          "id": "p1delay",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            110,
            150,
            22
          ],
          "text": "delay 300"
        }
      },
      {
        "box": {
          "id": "p1one",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            980,
            110,
            150,
            22
          ],
          "text": "1"
        }
      },
      {
        "box": {
          "id": "p1cancel",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            145,
            150,
            22
          ],
          "text": "stop"
        }
      },
      {
        "box": {
          "id": "p1off",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            145,
            150,
            22
          ],
          "text": "0"
        }
      },
      {
        "box": {
          "id": "p1pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            340,
            145,
            150,
            22
          ],
          "text": "36"
        }
      },
      {
        "box": {
          "id": "p1manual",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            500,
            145,
            150,
            22
          ],
          "text": "makenote 105 35"
        }
      },
      {
        "box": {
          "id": "p1out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            660,
            145,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "p2label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            820,
            145,
            150,
            22
          ],
          "text": "CC2 Snare",
          "presentation": 1,
          "presentation_rect": [
            155,
            76,
            130,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p2hit",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            980,
            145,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            155,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p2hold",
          "maxclass": "toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            20,
            180,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            193,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p2heldlabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            180,
            180,
            150,
            22
          ],
          "text": "Follow",
          "presentation": 1,
          "presentation_rect": [
            219,
            103,
            66,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p2raw",
          "maxclass": "number",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            340,
            180,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            155,
            136,
            45,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p2cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            500,
            180,
            150,
            22
          ],
          "text": "ctlin 2"
        }
      },
      {
        "box": {
          "id": "p2gt",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            660,
            180,
            150,
            22
          ],
          "text": "> 0"
        }
      },
      {
        "box": {
          "id": "p2edge",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            820,
            180,
            150,
            22
          ],
          "text": "change"
        }
      },
      {
        "box": {
          "id": "p2sel",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 3,
          "patching_rect": [
            980,
            180,
            150,
            22
          ],
          "text": "sel 1 0"
        }
      },
      {
        "box": {
          "id": "p2down",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            20,
            215,
            150,
            22
          ],
          "text": "t b b"
        }
      },
      {
        "box": {
          "id": "p2delay",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            215,
            150,
            22
          ],
          "text": "delay 300"
        }
      },
      {
        "box": {
          "id": "p2one",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            340,
            215,
            150,
            22
          ],
          "text": "1"
        }
      },
      {
        "box": {
          "id": "p2cancel",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            500,
            215,
            150,
            22
          ],
          "text": "stop"
        }
      },
      {
        "box": {
          "id": "p2off",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            660,
            215,
            150,
            22
          ],
          "text": "0"
        }
      },
      {
        "box": {
          "id": "p2pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            215,
            150,
            22
          ],
          "text": "38"
        }
      },
      {
        "box": {
          "id": "p2manual",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            980,
            215,
            150,
            22
          ],
          "text": "makenote 105 35"
        }
      },
      {
        "box": {
          "id": "p2out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            20,
            250,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "p3label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            180,
            250,
            150,
            22
          ],
          "text": "CC3 Hat",
          "presentation": 1,
          "presentation_rect": [
            300,
            76,
            130,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p3hit",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            340,
            250,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            300,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p3hold",
          "maxclass": "toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            500,
            250,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            338,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p3heldlabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            660,
            250,
            150,
            22
          ],
          "text": "Follow",
          "presentation": 1,
          "presentation_rect": [
            364,
            103,
            66,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p3raw",
          "maxclass": "number",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            820,
            250,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            300,
            136,
            45,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p3cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            980,
            250,
            150,
            22
          ],
          "text": "ctlin 3"
        }
      },
      {
        "box": {
          "id": "p3gt",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            285,
            150,
            22
          ],
          "text": "> 0"
        }
      },
      {
        "box": {
          "id": "p3edge",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            180,
            285,
            150,
            22
          ],
          "text": "change"
        }
      },
      {
        "box": {
          "id": "p3sel",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 3,
          "patching_rect": [
            340,
            285,
            150,
            22
          ],
          "text": "sel 1 0"
        }
      },
      {
        "box": {
          "id": "p3down",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            500,
            285,
            150,
            22
          ],
          "text": "t b b"
        }
      },
      {
        "box": {
          "id": "p3delay",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            660,
            285,
            150,
            22
          ],
          "text": "delay 300"
        }
      },
      {
        "box": {
          "id": "p3one",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            285,
            150,
            22
          ],
          "text": "1"
        }
      },
      {
        "box": {
          "id": "p3cancel",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            980,
            285,
            150,
            22
          ],
          "text": "stop"
        }
      },
      {
        "box": {
          "id": "p3off",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            320,
            150,
            22
          ],
          "text": "0"
        }
      },
      {
        "box": {
          "id": "p3pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            320,
            150,
            22
          ],
          "text": "42"
        }
      },
      {
        "box": {
          "id": "p3manual",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            340,
            320,
            150,
            22
          ],
          "text": "makenote 105 35"
        }
      },
      {
        "box": {
          "id": "p3out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            500,
            320,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "p4label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            660,
            320,
            150,
            22
          ],
          "text": "CC4 Perc",
          "presentation": 1,
          "presentation_rect": [
            445,
            76,
            130,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p4hit",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            820,
            320,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            445,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p4hold",
          "maxclass": "toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            980,
            320,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            483,
            102,
            22,
            22
          ]
        }
      },
      {
        "box": {
          "id": "p4heldlabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            20,
            355,
            150,
            22
          ],
          "text": "Follow",
          "presentation": 1,
          "presentation_rect": [
            509,
            103,
            66,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p4raw",
          "maxclass": "number",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            180,
            355,
            150,
            22
          ],
          "parameter_enable": 0,
          "presentation": 1,
          "presentation_rect": [
            445,
            136,
            45,
            20
          ]
        }
      },
      {
        "box": {
          "id": "p4cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            340,
            355,
            150,
            22
          ],
          "text": "ctlin 4"
        }
      },
      {
        "box": {
          "id": "p4gt",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            500,
            355,
            150,
            22
          ],
          "text": "> 0"
        }
      },
      {
        "box": {
          "id": "p4edge",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            660,
            355,
            150,
            22
          ],
          "text": "change"
        }
      },
      {
        "box": {
          "id": "p4sel",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 3,
          "patching_rect": [
            820,
            355,
            150,
            22
          ],
          "text": "sel 1 0"
        }
      },
      {
        "box": {
          "id": "p4down",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            980,
            355,
            150,
            22
          ],
          "text": "t b b"
        }
      },
      {
        "box": {
          "id": "p4delay",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            390,
            150,
            22
          ],
          "text": "delay 300"
        }
      },
      {
        "box": {
          "id": "p4one",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            390,
            150,
            22
          ],
          "text": "1"
        }
      },
      {
        "box": {
          "id": "p4cancel",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            340,
            390,
            150,
            22
          ],
          "text": "stop"
        }
      },
      {
        "box": {
          "id": "p4off",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            500,
            390,
            150,
            22
          ],
          "text": "0"
        }
      },
      {
        "box": {
          "id": "p4pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            660,
            390,
            150,
            22
          ],
          "text": "37"
        }
      },
      {
        "box": {
          "id": "p4manual",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            820,
            390,
            150,
            22
          ],
          "text": "makenote 105 35"
        }
      },
      {
        "box": {
          "id": "p4out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            980,
            390,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r36nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            20,
            425,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r36gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            425,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r36trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            340,
            425,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r36pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            500,
            425,
            150,
            22
          ],
          "text": "36"
        }
      },
      {
        "box": {
          "id": "r36note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            660,
            425,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r36out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            820,
            425,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r38nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            980,
            425,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r38gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            460,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r38trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            180,
            460,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r38pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            340,
            460,
            150,
            22
          ],
          "text": "38"
        }
      },
      {
        "box": {
          "id": "r38note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            500,
            460,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r38out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            660,
            460,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r42nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            820,
            460,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r42gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            980,
            460,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r42trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            20,
            495,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r42pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            180,
            495,
            150,
            22
          ],
          "text": "42"
        }
      },
      {
        "box": {
          "id": "r42note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            340,
            495,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r42out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            500,
            495,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r37nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            660,
            495,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r37gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            495,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r37trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            980,
            495,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r37pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            20,
            530,
            150,
            22
          ],
          "text": "37"
        }
      },
      {
        "box": {
          "id": "r37note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            180,
            530,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r37out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            340,
            530,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r56nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            500,
            530,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r56gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            660,
            530,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r56trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            820,
            530,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r56pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            980,
            530,
            150,
            22
          ],
          "text": "56"
        }
      },
      {
        "box": {
          "id": "r56note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            20,
            565,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r56out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            180,
            565,
            150,
            22
          ],
          "text": "noteout 10"
        }
      },
      {
        "box": {
          "id": "r45nonzero",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            340,
            565,
            150,
            22
          ],
          "text": "sel 0"
        }
      },
      {
        "box": {
          "id": "r45gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            500,
            565,
            150,
            22
          ],
          "text": "gate 1 0"
        }
      },
      {
        "box": {
          "id": "r45trig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            660,
            565,
            150,
            22
          ],
          "text": "t b i"
        }
      },
      {
        "box": {
          "id": "r45pitch",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "patching_rect": [
            820,
            565,
            150,
            22
          ],
          "text": "45"
        }
      },
      {
        "box": {
          "id": "r45note",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 2,
          "patching_rect": [
            980,
            565,
            150,
            22
          ],
          "text": "makenote 100 35"
        }
      },
      {
        "box": {
          "id": "r45out",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 0,
          "patching_rect": [
            20,
            600,
            150,
            22
          ],
          "text": "noteout 10"
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "source": [
            "stop",
            0
          ],
          "destination": [
            "zero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "notes",
            0
          ],
          "destination": [
            "pair",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "notes",
            1
          ],
          "destination": [
            "pair",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "pair",
            0
          ],
          "destination": [
            "route",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1cc",
            0
          ],
          "destination": [
            "p1raw",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1cc",
            0
          ],
          "destination": [
            "p1gt",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1gt",
            0
          ],
          "destination": [
            "p1edge",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1edge",
            0
          ],
          "destination": [
            "p1sel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1sel",
            0
          ],
          "destination": [
            "p1down",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1down",
            1
          ],
          "destination": [
            "p1hit",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1down",
            0
          ],
          "destination": [
            "p1delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1delay",
            0
          ],
          "destination": [
            "p1one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1one",
            0
          ],
          "destination": [
            "p1hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1sel",
            1
          ],
          "destination": [
            "p1cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1cancel",
            0
          ],
          "destination": [
            "p1delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1sel",
            1
          ],
          "destination": [
            "p1off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1off",
            0
          ],
          "destination": [
            "p1hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p1off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p1cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1hit",
            0
          ],
          "destination": [
            "p1pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1pitch",
            0
          ],
          "destination": [
            "p1manual",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1manual",
            0
          ],
          "destination": [
            "p1out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1manual",
            1
          ],
          "destination": [
            "p1out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2cc",
            0
          ],
          "destination": [
            "p2raw",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2cc",
            0
          ],
          "destination": [
            "p2gt",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2gt",
            0
          ],
          "destination": [
            "p2edge",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2edge",
            0
          ],
          "destination": [
            "p2sel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2sel",
            0
          ],
          "destination": [
            "p2down",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2down",
            1
          ],
          "destination": [
            "p2hit",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2down",
            0
          ],
          "destination": [
            "p2delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2delay",
            0
          ],
          "destination": [
            "p2one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2one",
            0
          ],
          "destination": [
            "p2hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2sel",
            1
          ],
          "destination": [
            "p2cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2cancel",
            0
          ],
          "destination": [
            "p2delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2sel",
            1
          ],
          "destination": [
            "p2off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2off",
            0
          ],
          "destination": [
            "p2hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p2off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p2cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2hit",
            0
          ],
          "destination": [
            "p2pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2pitch",
            0
          ],
          "destination": [
            "p2manual",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2manual",
            0
          ],
          "destination": [
            "p2out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2manual",
            1
          ],
          "destination": [
            "p2out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3cc",
            0
          ],
          "destination": [
            "p3raw",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3cc",
            0
          ],
          "destination": [
            "p3gt",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3gt",
            0
          ],
          "destination": [
            "p3edge",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3edge",
            0
          ],
          "destination": [
            "p3sel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3sel",
            0
          ],
          "destination": [
            "p3down",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3down",
            1
          ],
          "destination": [
            "p3hit",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3down",
            0
          ],
          "destination": [
            "p3delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3delay",
            0
          ],
          "destination": [
            "p3one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3one",
            0
          ],
          "destination": [
            "p3hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3sel",
            1
          ],
          "destination": [
            "p3cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3cancel",
            0
          ],
          "destination": [
            "p3delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3sel",
            1
          ],
          "destination": [
            "p3off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3off",
            0
          ],
          "destination": [
            "p3hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p3off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p3cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3hit",
            0
          ],
          "destination": [
            "p3pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3pitch",
            0
          ],
          "destination": [
            "p3manual",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3manual",
            0
          ],
          "destination": [
            "p3out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3manual",
            1
          ],
          "destination": [
            "p3out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4cc",
            0
          ],
          "destination": [
            "p4raw",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4cc",
            0
          ],
          "destination": [
            "p4gt",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4gt",
            0
          ],
          "destination": [
            "p4edge",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4edge",
            0
          ],
          "destination": [
            "p4sel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4sel",
            0
          ],
          "destination": [
            "p4down",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4down",
            1
          ],
          "destination": [
            "p4hit",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4down",
            0
          ],
          "destination": [
            "p4delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4delay",
            0
          ],
          "destination": [
            "p4one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4one",
            0
          ],
          "destination": [
            "p4hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4sel",
            1
          ],
          "destination": [
            "p4cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4cancel",
            0
          ],
          "destination": [
            "p4delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4sel",
            1
          ],
          "destination": [
            "p4off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4off",
            0
          ],
          "destination": [
            "p4hold",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p4off",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "p4cancel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4hit",
            0
          ],
          "destination": [
            "p4pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4pitch",
            0
          ],
          "destination": [
            "p4manual",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4manual",
            0
          ],
          "destination": [
            "p4out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4manual",
            1
          ],
          "destination": [
            "p4out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            0
          ],
          "destination": [
            "r36nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p1hold",
            0
          ],
          "destination": [
            "r36gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36nonzero",
            1
          ],
          "destination": [
            "r36gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36gate",
            0
          ],
          "destination": [
            "r36trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36trig",
            1
          ],
          "destination": [
            "r36note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36trig",
            0
          ],
          "destination": [
            "r36pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36pitch",
            0
          ],
          "destination": [
            "r36note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36note",
            0
          ],
          "destination": [
            "r36out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r36note",
            1
          ],
          "destination": [
            "r36out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            1
          ],
          "destination": [
            "r38nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p2hold",
            0
          ],
          "destination": [
            "r38gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38nonzero",
            1
          ],
          "destination": [
            "r38gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38gate",
            0
          ],
          "destination": [
            "r38trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38trig",
            1
          ],
          "destination": [
            "r38note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38trig",
            0
          ],
          "destination": [
            "r38pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38pitch",
            0
          ],
          "destination": [
            "r38note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38note",
            0
          ],
          "destination": [
            "r38out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r38note",
            1
          ],
          "destination": [
            "r38out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            2
          ],
          "destination": [
            "r42nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p3hold",
            0
          ],
          "destination": [
            "r42gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42nonzero",
            1
          ],
          "destination": [
            "r42gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42gate",
            0
          ],
          "destination": [
            "r42trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42trig",
            1
          ],
          "destination": [
            "r42note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42trig",
            0
          ],
          "destination": [
            "r42pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42pitch",
            0
          ],
          "destination": [
            "r42note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42note",
            0
          ],
          "destination": [
            "r42out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r42note",
            1
          ],
          "destination": [
            "r42out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            3
          ],
          "destination": [
            "r37nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4hold",
            0
          ],
          "destination": [
            "r37gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37nonzero",
            1
          ],
          "destination": [
            "r37gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37gate",
            0
          ],
          "destination": [
            "r37trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37trig",
            1
          ],
          "destination": [
            "r37note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37trig",
            0
          ],
          "destination": [
            "r37pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37pitch",
            0
          ],
          "destination": [
            "r37note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37note",
            0
          ],
          "destination": [
            "r37out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r37note",
            1
          ],
          "destination": [
            "r37out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            4
          ],
          "destination": [
            "r56nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4hold",
            0
          ],
          "destination": [
            "r56gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56nonzero",
            1
          ],
          "destination": [
            "r56gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56gate",
            0
          ],
          "destination": [
            "r56trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56trig",
            1
          ],
          "destination": [
            "r56note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56trig",
            0
          ],
          "destination": [
            "r56pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56pitch",
            0
          ],
          "destination": [
            "r56note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56note",
            0
          ],
          "destination": [
            "r56out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r56note",
            1
          ],
          "destination": [
            "r56out",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            5
          ],
          "destination": [
            "r45nonzero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "p4hold",
            0
          ],
          "destination": [
            "r45gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45nonzero",
            1
          ],
          "destination": [
            "r45gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45gate",
            0
          ],
          "destination": [
            "r45trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45trig",
            1
          ],
          "destination": [
            "r45note",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45trig",
            0
          ],
          "destination": [
            "r45pitch",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45pitch",
            0
          ],
          "destination": [
            "r45note",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45note",
            0
          ],
          "destination": [
            "r45out",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "r45note",
            1
          ],
          "destination": [
            "r45out",
            1
          ]
        }
      }
    ],
    "dependency_cache": [],
    "latency": 0,
    "is_mpe": 0,
    "external_mpe_tuning_enabled": 0,
    "minimum_live_version": "",
    "minimum_max_version": "",
    "platform_compatibility": 0,
    "project": {
      "version": 1,
      "creationdate": 3590052786,
      "modificationdate": 3590052786,
      "viewrect": [
        0.0,
        0.0,
        300.0,
        500.0
      ],
      "autoorganize": 1,
      "hideprojectwindow": 1,
      "showdependencies": 1,
      "autolocalize": 0,
      "contents": {
        "patchers": {}
      },
      "layout": {},
      "searchpath": {},
      "detailsvisible": 0,
      "amxdtype": 1835887981,
      "readonly": 0,
      "devpathtype": 0,
      "devpath": ".",
      "sortmode": 0,
      "viewmode": 0,
      "includepackages": 0
    },
    "autosave": 0,
    "oscreceiveudpport": 0,
    "openinpresentation": 1
  }
}