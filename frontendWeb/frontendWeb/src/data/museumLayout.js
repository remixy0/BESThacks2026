// Oficjalne dane Field Museum — Main Level (1:1 z field-museum-main-level.grid.json)
// Zawiera WSZYSTKIE obiekty: 25 Points of Interest, 84 Drzwi, 30 Sal.

export const MUSEUM_METADATA = {
  "schemaVersion": 1,
  "id": "field-museum-main-level",
  "name": "Field Museum — Main Level",
  "subtitle": "Chicago, IL • Plan Piętra Głównego (2D)",
  "units": "metres",
  "cellSizeM": 0.2,
  "width": 1066,
  "height": 681,
  "origin": {
    "x": -106.6,
    "y": -68.2
  },
  "coordinates": {
    "xAxis": "model +X (approximately east)",
    "yAxis": "model +Z (approximately south)",
    "modelToMap": {
      "x": "X",
      "y": "Z"
    },
    "rowDirection": "increasing y",
    "worldOrigin": "same as model; building centre",
    "gridOrigin": "minimum corner of cell [0,0]",
    "worldToCell": "column=floor((x-origin.x)/cellSizeM); row=floor((y-origin.y)/cellSizeM)",
    "cellToWorld": "x=origin.x+(column+0.5)*cellSizeM; y=origin.y+(row+0.5)*cellSizeM",
    "bounds": "minimum inclusive, maximum exclusive; reject out-of-range indices"
  },
  "encoding": "rows of single-character cell codes; cells[row][column]",
  "legend": {
    "0": "outside",
    "1": "walkable",
    "2": "geometry_obstacle",
    "3": "closed_or_staff_only",
    "4": "clearance_buffer",
    "5": "disconnected"
  },
  "navigation": {
    "walkableCode": "1",
    "neighbors": 4,
    "stepCostM": 0.2,
    "diagonalMoves": false,
    "pedestrianRadiusM": 0.3,
    "collisionHeightM": [
      0.02,
      1.9
    ],
    "rasterSubcellM": 0.05,
    "clearancePolicy": "conservative cell dilation: radius + full cell diagonal",
    "componentPolicy": "largest connected component only; other free cells code 5",
    "mapAlignmentRequired": true,
    "start": {
      "column": 530,
      "row": 600,
      "x": -0.5,
      "y": 51.9,
      "distanceToAnchorM": 0.141
    }
  },
  "source": {
    "model": "FieldMuseum_MainLevel.usdz",
    "modelSha256": "3a8e9583db5aab018bd7357d98951310472807bad85642f7bd30800f01c240f7",
    "info": "FieldMuseum_MainLevel_info.json",
    "infoSha256": "707743e1948290df53982088754820cd2e9b04e93228b9ba63270faa8e2134a5",
    "credit": "Floor-plan data © 2020 Field Museum of Natural History, CC BY 4.0",
    "url": "https://github.com/arcataroger/openlayers_indoor_map",
    "limitation": "Procedural reconstruction; walls, doors and furniture approximate reality."
  }
};

export const ROOMS = [
  {
    "id": "stanley_hall",
    "name": "Stanley Field Hall",
    "points": "379,140 640,140 640,550 379,550",
    "center": {
      "x": 510,
      "y": 275
    },
    "isExit": false
  },
  {
    "id": "south_entrance",
    "name": "South Entrance",
    "points": "480,620 588,620 588,665 480,665",
    "center": {
      "x": 534,
      "y": 632
    },
    "isExit": true
  },
  {
    "id": "north_entrance",
    "name": "North Entrance",
    "points": "480,15 588,15 588,60 480,60",
    "center": {
      "x": 534,
      "y": 48
    },
    "isEmergencyExit": true
  },
  {
    "id": "africa",
    "name": "Africa",
    "status": "open",
    "points": "379.4,311.9 378.4,440.3 80.6,440.4 80.6,371.3 121.9,371.2 121.8,312.1",
    "center": {
      "x": 238.5,
      "y": 378.5
    }
  },
  {
    "id": "Bird_Habitats",
    "name": "Bird Habitats",
    "status": "open",
    "points": "228.5,440.3 228.5,500.4 80.7,500.4 80.6,440.4",
    "center": {
      "x": 154.6,
      "y": 470.4
    }
  },
  {
    "id": "reptiles",
    "name": "Reptiles",
    "status": "open",
    "points": "228.5,440.3 316,440.3 316,500.3 228.5,500.4",
    "center": {
      "x": 272.2,
      "y": 470.3
    }
  },
  {
    "id": "animals",
    "name": "What Is an Animal?",
    "status": "open",
    "points": "80.7,500.4 378.6,500.3 378.5,576.6 80.6,576.8",
    "center": {
      "x": 229.6,
      "y": 538.5
    }
  },
  {
    "id": "mammals_4",
    "name": "Mammals of Africa",
    "status": "open",
    "points": "80.7,594.2 5.3,594.1 5,90.7 80.3,90.7",
    "center": {
      "x": 42.8,
      "y": 220
    }
  },
  {
    "id": "mammals_5",
    "name": "Mammals of Africa",
    "status": "open",
    "points": "80.4,244.1 328.3,244 380.1,244 379.4,311.9 80.5,312.1",
    "center": {
      "x": 230.1,
      "y": 278
    }
  },
  {
    "id": "rice",
    "name": "Plant Medicine",
    "status": "closed",
    "points": "121.8,312.1 121.9,371.2 80.6,371.3 80.5,312.1",
    "center": {
      "x": 101.2,
      "y": 341.7
    }
  },
  {
    "id": "birds",
    "name": "Birds",
    "status": "open",
    "points": "377.4,104.3 377.5,183.7 80.4,183.5 80.3,104.5",
    "center": {
      "x": 229,
      "y": 155
    }
  },
  {
    "id": "nature_walk",
    "name": "Nature Walk",
    "status": "open",
    "points": "406.3,243.8 80.4,244.1 80.4,183.5 406.2,183.2 406.2,174.6 448.6,174.6 448.8,254.4 406.3,254.4",
    "center": {
      "x": 270.3,
      "y": 213.8
    }
  },
  {
    "id": "mastaba",
    "name": "Inside Ancient Egypt",
    "status": "closed",
    "points": "400.6,421.9 444.8,421.9 444.8,519 400.7,519",
    "center": {
      "x": 422.7,
      "y": 442
    }
  },
  {
    "id": "sci_hub",
    "name": "Science Hub",
    "status": "open",
    "points": "666.6,462.5 619,462.5 619.1,415.4 666.7,415.5",
    "center": {
      "x": 642.8,
      "y": 439
    }
  },
  {
    "id": "fm_store",
    "name": "Museum Store",
    "status": "open",
    "points": "856.9,499.2 856.8,576.9 686.7,576.6 686.9,499",
    "center": {
      "x": 771.8,
      "y": 537.9
    }
  },
  {
    "id": "founders",
    "name": "Founders' Room",
    "status": "closed",
    "points": "672.9,576.6 672.7,646.5 658,646.7 630.5,646.3 618.2,646.3 618.1,576.7",
    "center": {
      "x": 645.5,
      "y": 611.5
    }
  },
  {
    "id": "pawnee_lodge",
    "name": "Pawnee Earth Lodge",
    "status": "closed",
    "points": "983.8,440.6 874,440.5 874.1,372.9 983.9,373",
    "center": {
      "x": 929,
      "y": 390
    }
  },
  {
    "id": "field_bistro",
    "name": "Field Bistro",
    "status": "closed",
    "points": "665.2,208.5 615.4,208.4 615.6,110.3 630.5,110.4 630.6,67.5 593.5,67.6 593.1,36 617.8,35.8 630.4,35.8 657.7,35.8 672.1,35.9 672.5,103.9 665.4,110.5",
    "center": {
      "x": 640.4,
      "y": 116.3
    }
  },
  {
    "id": "Room",
    "name": "Room",
    "status": "closed",
    "points": "726.4,104 726.3,179.8 688,179.7 688.1,103.9",
    "center": {
      "x": 707.2,
      "y": 141.8
    }
  },
  {
    "id": "StaffOnly",
    "name": "StaffOnly",
    "status": "staff_only",
    "points": "672.5,103.9 688.1,103.9 688,179.7 665.3,179.6 665.4,110.5",
    "center": {
      "x": 676.8,
      "y": 142.3
    }
  },
  {
    "id": "Room_2",
    "name": "Room_2",
    "status": "closed",
    "points": "984.1,244 984,310.9 665.1,310.4 665.2,243.4",
    "center": {
      "x": 824.6,
      "y": 277.2
    }
  },
  {
    "id": "Room_3",
    "name": "Room_3",
    "status": "closed",
    "points": "665.2,243.4 665.1,310.4 616.9,310.3 617.1,243.3",
    "center": {
      "x": 641.1,
      "y": 276.9
    }
  },
  {
    "id": "StaffOnly_2",
    "name": "StaffOnly_2",
    "status": "staff_only",
    "points": "984,310.9 983.9,373 899.5,372.9 899.6,310.8",
    "center": {
      "x": 941.7,
      "y": 341.9
    }
  },
  {
    "id": "apsaalooke",
    "name": "Apsáalooke Women and Warriors",
    "status": "open",
    "points": "874,440.5 686,440.2 686.1,372.6 750,372.6 750.1,310.5 899.6,310.8 899.5,372.9 874.1,372.9",
    "center": {
      "x": 798.9,
      "y": 379.2
    }
  },
  {
    "id": "americas",
    "name": "Ancient Americas",
    "status": "open",
    "points": "962.6,499.4 716.3,499.1 716.4,440.3 983.8,440.6 984.1,244 665.2,243.4 665.3,179.6 726.3,179.8 726.4,104 985.3,104.6 985.2,90.1 1060.7,90 1060.9,593.5 985.6,593.4 985.6,576.6 962.5,576.5 962.8,524.2 982.8,524 983.1,499.5",
    "center": {
      "x": 1022,
      "y": 340
    }
  },
  {
    "id": "StaffOnly_3",
    "name": "StaffOnly_3",
    "status": "staff_only",
    "points": "962.6,499.4 983.1,499.5 982.8,524 962.8,524.2 962.5,576.5 856.8,576 856.9,499.2",
    "center": {
      "x": 913.4,
      "y": 536.3
    }
  },
  {
    "id": "Room_4",
    "name": "Room_4",
    "status": "closed",
    "points": "750,372.6 665,372.5 665.1,310.4 750.1,310.5",
    "center": {
      "x": 707.6,
      "y": 341.5
    }
  },
  {
    "id": "StaffOnly_4",
    "name": "StaffOnly_4",
    "status": "staff_only",
    "points": "394.4,646.9 394.1,568.9 448,568.6 448.3,646.6 436.2,646.7 407.7,646.7",
    "center": {
      "x": 421.2,
      "y": 607.7
    }
  },
  {
    "id": "StaffOnly_5",
    "name": "StaffOnly_5",
    "status": "staff_only",
    "points": "316,440.3 400.6,440.3 400.6,500.3 316,500.3",
    "center": {
      "x": 358.3,
      "y": 470.3
    }
  },
  {
    "id": "StaffOnly_6",
    "name": "StaffOnly_6",
    "status": "staff_only",
    "points": "394.4,36.1 408,35.7 435,36 448.3,36 448.5,6 477.8,6.3 476.8,69.2 435.6,68.8 435.2,112 394.3,111.6",
    "center": {
      "x": 433.3,
      "y": 59.8
    }
  },
  {
    "id": "coat_check",
    "name": "Coat Check",
    "status": "closed",
    "points": "665.7,480.6 665.6,510.7 591.2,510.5 591.3,480.4",
    "center": {
      "x": 628.5,
      "y": 495.6
    }
  },
  {
    "id": "Space",
    "name": "Space",
    "status": "open",
    "points": "379.4,311.9 379.7,284.2 429.8,284.2 429.8,311.9",
    "center": {
      "x": 404.7,
      "y": 290
    }
  },
  {
    "id": "Slave_Ship",
    "name": "Africa",
    "status": "open",
    "points": "350.7,422.5 287.2,422.5 287.3,440.3 350.8,440.3",
    "center": {
      "x": 319,
      "y": 431.4
    }
  }
];

// Wszystkie 25 obiektów Points of Interest z pliku json (ekspozycje, udogodnienia, wejścia)
export const POINTS_OF_INTEREST = [
  {
    "id": "POI_south_entrance",
    "sourceId": "south_entrance",
    "kind": "entrance",
    "name": "South Entrance",
    "position": {
      "x": 0.26,
      "y": 61.1
    },
    "approach": {
      "column": 534,
      "row": 643,
      "x": 0.3,
      "y": 60.5,
      "distanceToAnchorM": 0.601
    },
    "unavailableReason": null,
    "x": 534.3,
    "y": 646.5,
    "icon": "🚪"
  },
  {
    "id": "POI_north_entrance",
    "sourceId": "north_entrance",
    "kind": "entrance",
    "name": "North Entrance",
    "position": {
      "x": 0.13,
      "y": -63.04
    },
    "approach": {
      "column": 533,
      "row": 29,
      "x": 0.1,
      "y": -62.3,
      "distanceToAnchorM": 0.741
    },
    "unavailableReason": null,
    "x": 533.6,
    "y": 25.8,
    "icon": "🚪"
  },
  {
    "id": "POI_maximo",
    "sourceId": "maximo",
    "kind": "exhibit",
    "name": "Máximo the Titanosaur",
    "position": {
      "x": -3,
      "y": -27
    },
    "approach": {
      "column": 500,
      "row": 202,
      "x": -6.5,
      "y": -27.7,
      "distanceToAnchorM": 3.569
    },
    "unavailableReason": null,
    "x": 518,
    "y": 206,
    "icon": "🦖"
  },
  {
    "id": "POI_elephants",
    "sourceId": "elephants",
    "kind": "exhibit",
    "name": "Fighting African Elephants",
    "position": {
      "x": -0.6,
      "y": -1
    },
    "approach": {
      "column": 529,
      "row": 320,
      "x": -0.7,
      "y": -4.1,
      "distanceToAnchorM": 3.102
    },
    "unavailableReason": null,
    "x": 530,
    "y": 336,
    "icon": "🐘"
  },
  {
    "id": "POI_totems",
    "sourceId": "totems",
    "kind": "exhibit",
    "name": "Totem Poles",
    "position": {
      "x": -0.6,
      "y": 17
    },
    "approach": {
      "column": 530,
      "row": 425,
      "x": -0.5,
      "y": 16.9,
      "distanceToAnchorM": 0.141
    },
    "unavailableReason": null,
    "x": 530,
    "y": 426,
    "icon": "🪵"
  },
  {
    "id": "POI_tsavo_lions",
    "sourceId": "tsavo_lions",
    "kind": "exhibit",
    "name": "The Lions of Tsavo",
    "position": {
      "x": -103.42,
      "y": -1.36
    },
    "approach": {
      "column": 26,
      "row": 334,
      "x": -101.3,
      "y": -1.3,
      "distanceToAnchorM": 2.121
    },
    "unavailableReason": null,
    "x": 15.9,
    "y": 334.2,
    "icon": "🦁"
  },
  {
    "id": "POI_seabirds",
    "sourceId": "seabirds",
    "kind": "exhibit",
    "name": "Plunge-Diving Seabirds",
    "position": {
      "x": -60.82,
      "y": -45.37
    },
    "approach": {
      "column": 228,
      "row": 123,
      "x": -60.9,
      "y": -43.5,
      "distanceToAnchorM": 1.872
    },
    "unavailableReason": null,
    "x": 228.9,
    "y": 114.2,
    "icon": "🦅"
  },
  {
    "id": "POI_mask",
    "sourceId": "mask",
    "kind": "exhibit",
    "name": "Greenstone Mask",
    "position": {
      "x": 41.68,
      "y": -22.94
    },
    "approach": {
      "column": 740,
      "row": 230,
      "x": 41.5,
      "y": -22.1,
      "distanceToAnchorM": 0.859
    },
    "unavailableReason": null,
    "x": 741.4,
    "y": 226.3,
    "icon": "🎭"
  },
  {
    "id": "POI_pawnee_lodge",
    "sourceId": "pawnee_lodge",
    "kind": "exhibit",
    "name": "Pawnee Earth Lodge",
    "position": {
      "x": 80.69,
      "y": 13.15
    },
    "approach": null,
    "unavailableReason": "closed_or_staff_only",
    "x": 936.4,
    "y": 406.8,
    "icon": "🛖"
  },
  {
    "id": "POI_mastaba",
    "sourceId": "mastaba",
    "kind": "exhibit",
    "name": "Mastaba Tomb Chapel",
    "position": {
      "x": -22.65,
      "y": 25.89
    },
    "approach": null,
    "unavailableReason": "closed_or_staff_only",
    "x": 419.7,
    "y": 470.4,
    "icon": "⚱️"
  },
  {
    "id": "Amenity_restroom_1",
    "sourceId": "restroom",
    "kind": "amenity",
    "name": "restroom",
    "position": {
      "x": -25.93,
      "y": -8.55
    },
    "approach": {
      "column": 403,
      "row": 298,
      "x": -25.9,
      "y": -8.5,
      "distanceToAnchorM": 0.058
    },
    "unavailableReason": null,
    "x": 403.3,
    "y": 298.3,
    "icon": "🚻"
  },
  {
    "id": "Amenity_stairs_up_down_1",
    "sourceId": "stairs_up_down",
    "kind": "amenity",
    "name": "stairs up down",
    "position": {
      "x": -28.54,
      "y": -41.72
    },
    "approach": {
      "column": 390,
      "row": 132,
      "x": -28.5,
      "y": -41.7,
      "distanceToAnchorM": 0.045
    },
    "unavailableReason": null,
    "x": 390.3,
    "y": 132.4,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_up_1",
    "sourceId": "stairs_up",
    "kind": "amenity",
    "name": "stairs up",
    "position": {
      "x": -16.73,
      "y": -50.21
    },
    "approach": {
      "column": 449,
      "row": 89,
      "x": -16.7,
      "y": -50.3,
      "distanceToAnchorM": 0.095
    },
    "unavailableReason": null,
    "x": 449.3,
    "y": 90,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_up_2",
    "sourceId": "stairs_up",
    "kind": "amenity",
    "name": "stairs up",
    "position": {
      "x": 16.34,
      "y": -50.1
    },
    "approach": {
      "column": 614,
      "row": 90,
      "x": 16.3,
      "y": -50.1,
      "distanceToAnchorM": 0.04
    },
    "unavailableReason": null,
    "x": 614.7,
    "y": 90.5,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_down_1",
    "sourceId": "stairs_down",
    "kind": "amenity",
    "name": "stairs down",
    "position": {
      "x": 22.13,
      "y": 0.02
    },
    "approach": {
      "column": 643,
      "row": 341,
      "x": 22.1,
      "y": 0.1,
      "distanceToAnchorM": 0.085
    },
    "unavailableReason": null,
    "x": 643.6,
    "y": 341.1,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_down_2",
    "sourceId": "stairs_down",
    "kind": "amenity",
    "name": "stairs down",
    "position": {
      "x": -21.93,
      "y": 0.16
    },
    "approach": {
      "column": 423,
      "row": 341,
      "x": -21.9,
      "y": 0.1,
      "distanceToAnchorM": 0.067
    },
    "unavailableReason": null,
    "x": 423.3,
    "y": 341.8,
    "icon": "🪜"
  },
  {
    "id": "Amenity_elevator_1",
    "sourceId": "elevator",
    "kind": "amenity",
    "name": "elevator",
    "position": {
      "x": -27.63,
      "y": 8.46
    },
    "approach": {
      "column": 394,
      "row": 383,
      "x": -27.7,
      "y": 8.5,
      "distanceToAnchorM": 0.081
    },
    "unavailableReason": null,
    "x": 394.8,
    "y": 383.3,
    "icon": "🛗"
  },
  {
    "id": "Amenity_elevator_2",
    "sourceId": "elevator",
    "kind": "amenity",
    "name": "elevator",
    "position": {
      "x": 27.65,
      "y": 8.53
    },
    "approach": {
      "column": 671,
      "row": 383,
      "x": 27.7,
      "y": 8.5,
      "distanceToAnchorM": 0.058
    },
    "unavailableReason": null,
    "x": 671.3,
    "y": 383.6,
    "icon": "🛗"
  },
  {
    "id": "Amenity_store_1",
    "sourceId": "store",
    "kind": "amenity",
    "name": "store",
    "position": {
      "x": 33.93,
      "y": 38.99
    },
    "approach": {
      "column": 702,
      "row": 535,
      "x": 33.9,
      "y": 38.9,
      "distanceToAnchorM": 0.095
    },
    "unavailableReason": null,
    "x": 702.6,
    "y": 535.9,
    "icon": "🛍️"
  },
  {
    "id": "Amenity_atm_1",
    "sourceId": "atm",
    "kind": "amenity",
    "name": "atm",
    "position": {
      "x": -2.15,
      "y": 59.18
    },
    "approach": {
      "column": 522,
      "row": 636,
      "x": -2.1,
      "y": 59.1,
      "distanceToAnchorM": 0.094
    },
    "unavailableReason": null,
    "x": 522.2,
    "y": 636.9,
    "icon": "🏧"
  },
  {
    "id": "Amenity_stairs_up_3",
    "sourceId": "stairs_up",
    "kind": "amenity",
    "name": "stairs up",
    "position": {
      "x": -4.48,
      "y": 47.39
    },
    "approach": {
      "column": 510,
      "row": 577,
      "x": -4.5,
      "y": 47.3,
      "distanceToAnchorM": 0.092
    },
    "unavailableReason": null,
    "x": 510.6,
    "y": 577.9,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_up_down_2",
    "sourceId": "stairs_up_down",
    "kind": "amenity",
    "name": "stairs up down",
    "position": {
      "x": -28.37,
      "y": 42.27
    },
    "approach": {
      "column": 391,
      "row": 552,
      "x": -28.3,
      "y": 42.3,
      "distanceToAnchorM": 0.076
    },
    "unavailableReason": null,
    "x": 391.1,
    "y": 552.3,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_up_4",
    "sourceId": "stairs_up",
    "kind": "amenity",
    "name": "stairs up",
    "position": {
      "x": -88.18,
      "y": -41.68
    },
    "approach": {
      "column": 92,
      "row": 132,
      "x": -88.1,
      "y": -41.7,
      "distanceToAnchorM": 0.082
    },
    "unavailableReason": null,
    "x": 92.1,
    "y": 132.6,
    "icon": "🪜"
  },
  {
    "id": "Amenity_stairs_up_5",
    "sourceId": "stairs_up",
    "kind": "amenity",
    "name": "stairs up",
    "position": {
      "x": 88.19,
      "y": 42.09
    },
    "approach": {
      "column": 973,
      "row": 551,
      "x": 88.1,
      "y": 42.1,
      "distanceToAnchorM": 0.091
    },
    "unavailableReason": null,
    "x": 973.9,
    "y": 551.5,
    "icon": "🪜"
  },
  {
    "id": "Amenity_store_2",
    "sourceId": "store",
    "kind": "amenity",
    "name": "store",
    "position": {
      "x": 63.64,
      "y": 15.99
    },
    "approach": {
      "column": 851,
      "row": 420,
      "x": 63.7,
      "y": 15.9,
      "distanceToAnchorM": 0.108
    },
    "unavailableReason": null,
    "x": 851.2,
    "y": 420.9,
    "icon": "🛍️"
  }
];


// Wszystkie 84 drzwi z pliku json łączących pomieszczenia
export const DOORS = [
  {
    "id": "door_1",
    "position": {
      "x": -31.05,
      "y": 38.99
    },
    "widthM": 4,
    "sourceConnects": [
      "animals",
      "hall"
    ],
    "x": 377.7,
    "y": 535.9,
    "widthPx": 20
  },
  {
    "id": "door_2",
    "position": {
      "x": -30.83,
      "y": 10.03
    },
    "widthM": 4,
    "sourceConnects": [
      "africa",
      "hall"
    ],
    "x": 378.8,
    "y": 391.1,
    "widthPx": 20
  },
  {
    "id": "door_3",
    "position": {
      "x": -30.69,
      "y": -9.59
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "staff"
    ],
    "x": 379.5,
    "y": 293,
    "widthPx": 13
  },
  {
    "id": "door_4",
    "position": {
      "x": -79.8,
      "y": 19.87
    },
    "widthM": 2.6,
    "sourceConnects": [
      "africa",
      "birds"
    ],
    "x": 134,
    "y": 440.4,
    "widthPx": 13
  },
  {
    "id": "door_5",
    "position": {
      "x": -58.47,
      "y": 19.86
    },
    "widthM": 2.6,
    "sourceConnects": [
      "africa",
      "animals"
    ],
    "x": 240.6,
    "y": 440.3,
    "widthPx": 13
  },
  {
    "id": "door_6",
    "position": {
      "x": -37.14,
      "y": 19.85
    },
    "widthM": 2.6,
    "sourceConnects": [
      "africa",
      "staff"
    ],
    "x": 347.3,
    "y": 440.3,
    "widthPx": 13
  },
  {
    "id": "door_7",
    "position": {
      "x": 45.49,
      "y": 19.82
    },
    "widthM": 2.6,
    "sourceConnects": [
      "apsaalooke",
      "americas"
    ],
    "x": 760.4,
    "y": 440.1,
    "widthPx": 13
  },
  {
    "id": "door_8",
    "position": {
      "x": 75.27,
      "y": 19.8
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "americas"
    ],
    "x": 909.4,
    "y": 440,
    "widthPx": 13
  },
  {
    "id": "door_9",
    "position": {
      "x": -90.45,
      "y": 34.58
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "animals"
    ],
    "x": 80.7,
    "y": 513.9,
    "widthPx": 13
  },
  {
    "id": "door_10",
    "position": {
      "x": -90.48,
      "y": 11.47
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "africa"
    ],
    "x": 80.6,
    "y": 398.3,
    "widthPx": 13
  },
  {
    "id": "door_11",
    "position": {
      "x": -90.5,
      "y": -11.64
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "mammals"
    ],
    "x": 80.5,
    "y": 282.8,
    "widthPx": 13
  },
  {
    "id": "door_12",
    "position": {
      "x": -90.53,
      "y": -34.74
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "birds"
    ],
    "x": 80.3,
    "y": 167.3,
    "widthPx": 13
  },
  {
    "id": "door_13",
    "position": {
      "x": -86.35,
      "y": 6.04
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "africa"
    ],
    "x": 101.3,
    "y": 371.2,
    "widthPx": 13
  },
  {
    "id": "door_14",
    "position": {
      "x": 34.9,
      "y": 5.99
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "apsaalooke"
    ],
    "x": 707.5,
    "y": 370.9,
    "widthPx": 13
  },
  {
    "id": "door_15",
    "position": {
      "x": 79.2,
      "y": 5.97
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "americas"
    ],
    "x": 929,
    "y": 370.8,
    "widthPx": 13
  },
  {
    "id": "door_16",
    "position": {
      "x": -82.23,
      "y": 0.13
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "africa"
    ],
    "x": 121.8,
    "y": 341.6,
    "widthPx": 13
  },
  {
    "id": "door_17",
    "position": {
      "x": -75.55,
      "y": -5.79
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "africa"
    ],
    "x": 155.2,
    "y": 312.1,
    "widthPx": 13
  },
  {
    "id": "door_18",
    "position": {
      "x": -45.66,
      "y": -5.8
    },
    "widthM": 2.6,
    "sourceConnects": [
      "mammals",
      "africa"
    ],
    "x": 304.7,
    "y": 312,
    "widthPx": 13
  },
  {
    "id": "door_19",
    "position": {
      "x": 29.03,
      "y": -5.84
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "staff"
    ],
    "x": 678.1,
    "y": 311.8,
    "widthPx": 13
  },
  {
    "id": "door_20",
    "position": {
      "x": 53.5,
      "y": -5.85
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "apsaalooke"
    ],
    "x": 800.5,
    "y": 311.8,
    "widthPx": 13
  },
  {
    "id": "door_21",
    "position": {
      "x": 77.97,
      "y": -5.86
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "staff"
    ],
    "x": 922.8,
    "y": 311.7,
    "widthPx": 13
  },
  {
    "id": "door_22",
    "position": {
      "x": -60.9,
      "y": 25.87
    },
    "widthM": 2.6,
    "sourceConnects": [
      "birds",
      "animals"
    ],
    "x": 228.5,
    "y": 470.4,
    "widthPx": 13
  },
  {
    "id": "door_23",
    "position": {
      "x": -79.79,
      "y": 31.88
    },
    "widthM": 2.6,
    "sourceConnects": [
      "birds",
      "animals"
    ],
    "x": 134,
    "y": 500.4,
    "widthPx": 13
  },
  {
    "id": "door_24",
    "position": {
      "x": -58.46,
      "y": 31.87
    },
    "widthM": 2.6,
    "sourceConnects": [
      "animals",
      "animals"
    ],
    "x": 240.7,
    "y": 500.4,
    "widthPx": 13
  },
  {
    "id": "door_25",
    "position": {
      "x": -37.13,
      "y": 31.86
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "animals"
    ],
    "x": 347.3,
    "y": 500.3,
    "widthPx": 13
  },
  {
    "id": "door_26",
    "position": {
      "x": 45.58,
      "y": 31.82
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "store"
    ],
    "x": 760.9,
    "y": 500.1,
    "widthPx": 13
  },
  {
    "id": "door_27",
    "position": {
      "x": 75.2,
      "y": 31.81
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "staff"
    ],
    "x": 909,
    "y": 500.1,
    "widthPx": 13
  },
  {
    "id": "door_28",
    "position": {
      "x": -43.4,
      "y": 25.86
    },
    "widthM": 2.6,
    "sourceConnects": [
      "animals",
      "staff"
    ],
    "x": 316,
    "y": 470.3,
    "widthPx": 13
  },
  {
    "id": "door_29",
    "position": {
      "x": 21.99,
      "y": 47.1
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 642.9,
    "y": 576.5,
    "widthPx": 20
  },
  {
    "id": "door_30",
    "position": {
      "x": -79.65,
      "y": -19.38
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "mammals"
    ],
    "x": 134.7,
    "y": 244.1,
    "widthPx": 13
  },
  {
    "id": "door_31",
    "position": {
      "x": -57.93,
      "y": -19.39
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "mammals"
    ],
    "x": 243.3,
    "y": 244.1,
    "widthPx": 13
  },
  {
    "id": "door_32",
    "position": {
      "x": -36.21,
      "y": -19.4
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "mammals"
    ],
    "x": 351.9,
    "y": 244,
    "widthPx": 13
  },
  {
    "id": "door_33",
    "position": {
      "x": 29.05,
      "y": -19.43
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "staff"
    ],
    "x": 678.3,
    "y": 243.8,
    "widthPx": 13
  },
  {
    "id": "door_34",
    "position": {
      "x": 53.52,
      "y": -19.44
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "staff"
    ],
    "x": 800.6,
    "y": 243.8,
    "widthPx": 13
  },
  {
    "id": "door_35",
    "position": {
      "x": 77.99,
      "y": -19.46
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "staff"
    ],
    "x": 922.9,
    "y": 243.7,
    "widthPx": 13
  },
  {
    "id": "door_36",
    "position": {
      "x": -31.11,
      "y": -38.89
    },
    "widthM": 4,
    "sourceConnects": [
      "birds",
      "hall"
    ],
    "x": 377.4,
    "y": 146.6,
    "widthPx": 20
  },
  {
    "id": "door_37",
    "position": {
      "x": -36.22,
      "y": -31.46
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "birds"
    ],
    "x": 351.9,
    "y": 183.7,
    "widthPx": 13
  },
  {
    "id": "door_38",
    "position": {
      "x": -57.94,
      "y": -31.48
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "birds"
    ],
    "x": 243.3,
    "y": 183.6,
    "widthPx": 13
  },
  {
    "id": "door_39",
    "position": {
      "x": -79.66,
      "y": -31.49
    },
    "widthM": 2.6,
    "sourceConnects": [
      "nature",
      "birds"
    ],
    "x": 134.7,
    "y": 183.6,
    "widthPx": 13
  },
  {
    "id": "door_40",
    "position": {
      "x": -21.11,
      "y": -33.29
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "nature"
    ],
    "x": 427.4,
    "y": 174.6,
    "widthPx": 20
  },
  {
    "id": "door_41",
    "position": {
      "x": -16.78,
      "y": 52.83
    },
    "widthM": 4,
    "sourceConnects": [
      "staff",
      "hall"
    ],
    "x": 449.1,
    "y": 605.1,
    "widthPx": 20
  },
  {
    "id": "door_42",
    "position": {
      "x": -16.86,
      "y": -25.31
    },
    "widthM": 4,
    "sourceConnects": [
      "nature",
      "hall"
    ],
    "x": 448.7,
    "y": 214.4,
    "widthPx": 20
  },
  {
    "id": "door_43",
    "position": {
      "x": -21.1,
      "y": -17.32
    },
    "widthM": 4,
    "sourceConnects": [
      "nature",
      "hall"
    ],
    "x": 427.5,
    "y": 254.4,
    "widthPx": 20
  },
  {
    "id": "door_44",
    "position": {
      "x": -22.06,
      "y": 16.19
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "egypt"
    ],
    "x": 422.7,
    "y": 421.9,
    "widthPx": 20
  },
  {
    "id": "door_45",
    "position": {
      "x": -17.64,
      "y": 25.89
    },
    "widthM": 4,
    "sourceConnects": [
      "egypt",
      "hall"
    ],
    "x": 444.8,
    "y": 470.4,
    "widthPx": 20
  },
  {
    "id": "door_46",
    "position": {
      "x": -22.05,
      "y": 35.59
    },
    "widthM": 4,
    "sourceConnects": [
      "egypt",
      "hall"
    ],
    "x": 422.7,
    "y": 519,
    "widthPx": 20
  },
  {
    "id": "door_47",
    "position": {
      "x": -26.47,
      "y": 25.89
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "egypt"
    ],
    "x": 400.6,
    "y": 470.4,
    "widthPx": 13
  },
  {
    "id": "door_48",
    "position": {
      "x": 21.96,
      "y": 24.3
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "white"
    ],
    "x": 642.8,
    "y": 462.5,
    "widthPx": 20
  },
  {
    "id": "door_49",
    "position": {
      "x": 17.16,
      "y": 53.6
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 618.8,
    "y": 609,
    "widthPx": 20
  },
  {
    "id": "door_50",
    "position": {
      "x": 17.21,
      "y": 19.59
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "white"
    ],
    "x": 619,
    "y": 438.9,
    "widthPx": 20
  },
  {
    "id": "door_51",
    "position": {
      "x": 17.27,
      "y": -12.83
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "staff"
    ],
    "x": 619.3,
    "y": 276.9,
    "widthPx": 20
  },
  {
    "id": "door_52",
    "position": {
      "x": 21.98,
      "y": 14.9
    },
    "widthM": 4,
    "sourceConnects": [
      "white",
      "hall"
    ],
    "x": 642.9,
    "y": 415.5,
    "widthPx": 20
  },
  {
    "id": "door_53",
    "position": {
      "x": 26.71,
      "y": 30.93
    },
    "widthM": 4,
    "sourceConnects": [
      "warm",
      "hall"
    ],
    "x": 666.5,
    "y": 495.6,
    "widthPx": 20
  },
  {
    "id": "door_54",
    "position": {
      "x": 26.73,
      "y": 19.61
    },
    "widthM": 4,
    "sourceConnects": [
      "white",
      "hall"
    ],
    "x": 666.6,
    "y": 439.1,
    "widthPx": 20
  },
  {
    "id": "door_55",
    "position": {
      "x": 26.77,
      "y": -6.8
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "staff"
    ],
    "x": 666.9,
    "y": 307,
    "widthPx": 13
  },
  {
    "id": "door_56",
    "position": {
      "x": 26.82,
      "y": -33
    },
    "widthM": 2.6,
    "sourceConnects": [
      "warm",
      "staff"
    ],
    "x": 667.1,
    "y": 176,
    "widthPx": 13
  },
  {
    "id": "door_57",
    "position": {
      "x": 64.78,
      "y": 38.92
    },
    "widthM": 2.6,
    "sourceConnects": [
      "store",
      "staff"
    ],
    "x": 856.9,
    "y": 535.6,
    "widthPx": 13
  },
  {
    "id": "door_58",
    "position": {
      "x": 30.75,
      "y": 38.86
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "store"
    ],
    "x": 686.7,
    "y": 535.3,
    "widthPx": 20
  },
  {
    "id": "door_59",
    "position": {
      "x": 30.8,
      "y": 13.07
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "apsaalooke"
    ],
    "x": 687,
    "y": 406.4,
    "widthPx": 20
  },
  {
    "id": "door_60",
    "position": {
      "x": 30.89,
      "y": -39.33
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "staff"
    ],
    "x": 687.5,
    "y": 144.4,
    "widthPx": 13
  },
  {
    "id": "door_61",
    "position": {
      "x": 68.21,
      "y": 13.14
    },
    "widthM": 2.6,
    "sourceConnects": [
      "apsaalooke",
      "americas"
    ],
    "x": 874,
    "y": 406.7,
    "widthPx": 13
  },
  {
    "id": "door_62",
    "position": {
      "x": 90.14,
      "y": 34.15
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "americas"
    ],
    "x": 983.7,
    "y": 511.7,
    "widthPx": 13
  },
  {
    "id": "door_63",
    "position": {
      "x": 90.18,
      "y": 10.1
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "americas"
    ],
    "x": 983.9,
    "y": 391.5,
    "widthPx": 13
  },
  {
    "id": "door_64",
    "position": {
      "x": 90.21,
      "y": -9.57
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "americas"
    ],
    "x": 984,
    "y": 293.1,
    "widthPx": 13
  },
  {
    "id": "door_65",
    "position": {
      "x": 21.47,
      "y": -26.51
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 640.3,
    "y": 208.4,
    "widthPx": 20
  },
  {
    "id": "door_66",
    "position": {
      "x": 16.51,
      "y": -36.32
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 615.5,
    "y": 159.4,
    "widthPx": 20
  },
  {
    "id": "door_67",
    "position": {
      "x": -23.65,
      "y": -46.2
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "staff"
    ],
    "x": 414.7,
    "y": 110,
    "widthPx": 20
  },
  {
    "id": "door_68",
    "position": {
      "x": 19.51,
      "y": -50.41
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 630.5,
    "y": 89,
    "widthPx": 20
  },
  {
    "id": "door_69",
    "position": {
      "x": -15.36,
      "y": -54.65
    },
    "widthM": 4,
    "sourceConnects": [
      "staff",
      "hall"
    ],
    "x": 456.2,
    "y": 67.8,
    "widthPx": 20
  },
  {
    "id": "door_70",
    "position": {
      "x": 15.81,
      "y": -54.7
    },
    "widthM": 4,
    "sourceConnects": [
      "warm",
      "hall"
    ],
    "x": 612,
    "y": 67.5,
    "widthPx": 20
  },
  {
    "id": "door_71",
    "position": {
      "x": 12.07,
      "y": -57.84
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 593.3,
    "y": 51.8,
    "widthPx": 20
  },
  {
    "id": "door_72",
    "position": {
      "x": 14.03,
      "y": -61.01
    },
    "widthM": 3.01,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 603.1,
    "y": 36,
    "widthPx": 15
  },
  {
    "id": "door_73",
    "position": {
      "x": 38.67,
      "y": -39.32
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "americas"
    ],
    "x": 726.3,
    "y": 144.4,
    "widthPx": 13
  },
  {
    "id": "door_74",
    "position": {
      "x": 32.56,
      "y": -32.26
    },
    "widthM": 2.6,
    "sourceConnects": [
      "americas",
      "staff"
    ],
    "x": 695.8,
    "y": 179.7,
    "widthPx": 13
  },
  {
    "id": "door_75",
    "position": {
      "x": 73.31,
      "y": 0.17
    },
    "widthM": 2.6,
    "sourceConnects": [
      "apsaalooke",
      "staff"
    ],
    "x": 899.5,
    "y": 341.9,
    "widthPx": 13
  },
  {
    "id": "door_76",
    "position": {
      "x": 43.41,
      "y": 0.12
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "apsaalooke"
    ],
    "x": 750,
    "y": 341.6,
    "widthPx": 13
  },
  {
    "id": "door_77",
    "position": {
      "x": 36.68,
      "y": 25.73
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "americas"
    ],
    "x": 716.4,
    "y": 469.7,
    "widthPx": 20
  },
  {
    "id": "door_78",
    "position": {
      "x": 85.93,
      "y": 41.35
    },
    "widthM": 2.6,
    "sourceConnects": [
      "staff",
      "americas"
    ],
    "x": 962.6,
    "y": 547.8,
    "widthPx": 13
  },
  {
    "id": "door_79",
    "position": {
      "x": -22.39,
      "y": 45.55
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "staff"
    ],
    "x": 421,
    "y": 568.8,
    "widthPx": 20
  },
  {
    "id": "door_80",
    "position": {
      "x": -11.17,
      "y": -58.77
    },
    "widthM": 4,
    "sourceConnects": [
      "staff",
      "hall"
    ],
    "x": 477.1,
    "y": 47.1,
    "widthPx": 20
  },
  {
    "id": "door_81",
    "position": {
      "x": -19.51,
      "y": -50.12
    },
    "widthM": 4,
    "sourceConnects": [
      "staff",
      "hall"
    ],
    "x": 435.4,
    "y": 90.4,
    "widthPx": 20
  },
  {
    "id": "door_82",
    "position": {
      "x": 19.08,
      "y": 33.93
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 628.4,
    "y": 510.6,
    "widthPx": 20
  },
  {
    "id": "door_83",
    "position": {
      "x": 11.64,
      "y": 30.9
    },
    "widthM": 4,
    "sourceConnects": [
      "hall",
      "warm"
    ],
    "x": 591.2,
    "y": 495.5,
    "widthPx": 20
  },
  {
    "id": "door_84",
    "position": {
      "x": 19.09,
      "y": 27.9
    },
    "widthM": 4,
    "sourceConnects": [
      "warm",
      "hall"
    ],
    "x": 628.4,
    "y": 480.5,
    "widthPx": 20
  }
];

export const INITIAL_VISITORS = [];

export const SAMPLE_PROBLEMS = [
  "Zgubił bilet wstępu",
  "Źle się poczuł (potrzebna woda)",
  "Zgubił dziecko w galerii",
  "Awaria audioprzewodnika",
  "Nie wie jak dojść do wyjścia"
];

export const DEFAULT_HAZARDS = [
  {
    "id": "wet_floor",
    "name": "Mokra podłoga",
    "icon": "🧹",
    "color": "#f59e0b",
    "bgColor": "rgba(245, 158, 11, 0.25)",
    "borderColor": "#f59e0b"
  },
  {
    "id": "damaged_surface",
    "name": "Uszkodzona nawierzchnia",
    "icon": "⚠️",
    "color": "#ef4444",
    "bgColor": "rgba(239, 68, 68, 0.25)",
    "borderColor": "#ef4444"
  },
  {
    "id": "trash_on_floor",
    "name": "Śmieci na podłodze",
    "icon": "🗑️",
    "color": "#8b5cf6",
    "bgColor": "rgba(139, 92, 246, 0.25)",
    "borderColor": "#8b5cf6"
  }
];

export const ROOM_HAZARDS = DEFAULT_HAZARDS;
