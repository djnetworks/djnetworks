-- 0005_seed_taxonomy.sql
-- 27 categories, 187 subcategories.
--
-- PROVENANCE: this taxonomy was drafted in an earlier planning session, NOT by the business
-- owner. It is a starting point, not a validated list. Before intake begins he must walk it and
-- strike out what the business does not own — otherwise the product master offers 187 choices
-- for a fleet that probably spans 40 of them.
--
-- Pooled categories (counted, never numbered) per the tracking_mode decision:
--   Cable, Mic accessory, Stand & rigging, Tool & spare
-- Consumable category is issued-and-charged, never expected back.
-- Tool & spare is additionally flagged not rentable.

insert into category (name, sort_order) values ('DJ', 10) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Speaker', 20) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Amplifier', 30) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Mixer', 40) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Microphone', 50) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Mic accessory', 60) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Signal', 70) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Playback', 80) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Lighting - static', 90) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Lighting - moving', 100) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Lighting - effect', 110) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Lighting - control', 120) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Visual', 130) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Effects', 140) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Truss', 150) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Stand & rigging', 160) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Stage', 170) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Power', 180) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Cable', 190) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Backline - keys', 200) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Backline - drums', 210) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Backline - guitar', 220) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Backline - other', 230) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Case & transport', 240) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Consumable', 250) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Tool & spare', 260) on conflict (name) do nothing;
insert into category (name, sort_order) values ('Other', 270) on conflict (name) do nothing;

-- DJ
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'DJ'), 'CD / USB player', 10),
  ((select id from category where name = 'DJ'), 'Turntable', 20),
  ((select id from category where name = 'DJ'), 'DJ mixer - 2 channel', 30),
  ((select id from category where name = 'DJ'), 'DJ mixer - 4 channel', 40),
  ((select id from category where name = 'DJ'), 'All-in-one controller', 50),
  ((select id from category where name = 'DJ'), 'Pad / effects controller', 60),
  ((select id from category where name = 'DJ'), 'DJ headphones', 70),
  ((select id from category where name = 'DJ'), 'Booth facade', 80),
  ((select id from category where name = 'DJ'), 'Laptop stand', 90),
  ((select id from category where name = 'DJ'), 'Rekordbox / USB drive', 100)
on conflict (category_id, name) do nothing;

-- Speaker
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Speaker'), 'Top - full range 10"', 10),
  ((select id from category where name = 'Speaker'), 'Top - full range 12"', 20),
  ((select id from category where name = 'Speaker'), 'Top - full range 15"', 30),
  ((select id from category where name = 'Speaker'), 'Subwoofer 15"', 40),
  ((select id from category where name = 'Speaker'), 'Subwoofer 18"', 50),
  ((select id from category where name = 'Speaker'), 'Subwoofer - double 18"', 60),
  ((select id from category where name = 'Speaker'), 'Line array cabinet', 70),
  ((select id from category where name = 'Speaker'), 'Line array sub', 80),
  ((select id from category where name = 'Speaker'), 'Stage monitor / wedge', 90),
  ((select id from category where name = 'Speaker'), 'Column / pillar speaker', 100),
  ((select id from category where name = 'Speaker'), 'Coaxial / point source', 110),
  ((select id from category where name = 'Speaker'), 'Passive cabinet', 120)
on conflict (category_id, name) do nothing;

-- Amplifier
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Amplifier'), 'Power amplifier', 10),
  ((select id from category where name = 'Amplifier'), 'Speaker processor / DSP', 20),
  ((select id from category where name = 'Amplifier'), 'Crossover', 30),
  ((select id from category where name = 'Amplifier'), 'Rack case - amp', 40)
on conflict (category_id, name) do nothing;

-- Mixer
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Mixer'), 'Analogue mixer - 8ch', 10),
  ((select id from category where name = 'Mixer'), 'Analogue mixer - 16ch', 20),
  ((select id from category where name = 'Mixer'), 'Analogue mixer - 24ch', 30),
  ((select id from category where name = 'Mixer'), 'Digital mixing desk', 40),
  ((select id from category where name = 'Mixer'), 'Rack mixer', 50),
  ((select id from category where name = 'Mixer'), 'Stage box / digital snake', 60)
on conflict (category_id, name) do nothing;

-- Microphone
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Microphone'), 'Wired dynamic', 10),
  ((select id from category where name = 'Microphone'), 'Wired condenser', 20),
  ((select id from category where name = 'Microphone'), 'Instrument mic', 30),
  ((select id from category where name = 'Microphone'), 'Shotgun mic', 40),
  ((select id from category where name = 'Microphone'), 'Boundary / table mic', 50),
  ((select id from category where name = 'Microphone'), 'Wireless handheld set', 60),
  ((select id from category where name = 'Microphone'), 'Wireless lapel / collar set', 70),
  ((select id from category where name = 'Microphone'), 'Wireless headworn set', 80),
  ((select id from category where name = 'Microphone'), 'Wireless instrument set', 90),
  ((select id from category where name = 'Microphone'), 'Antenna / booster', 100)
on conflict (category_id, name) do nothing;

-- Mic accessory
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Mic accessory'), 'Boom stand', 10),
  ((select id from category where name = 'Mic accessory'), 'Straight stand', 20),
  ((select id from category where name = 'Mic accessory'), 'Short / desk stand', 30),
  ((select id from category where name = 'Mic accessory'), 'Mic clip', 40),
  ((select id from category where name = 'Mic accessory'), 'Pop filter', 50),
  ((select id from category where name = 'Mic accessory'), 'Windscreen', 60),
  ((select id from category where name = 'Mic accessory'), 'Gooseneck', 70)
on conflict (category_id, name) do nothing;

-- Signal
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Signal'), 'DI box - active', 10),
  ((select id from category where name = 'Signal'), 'DI box - passive', 20),
  ((select id from category where name = 'Signal'), 'Splitter', 30),
  ((select id from category where name = 'Signal'), 'Isolator', 40),
  ((select id from category where name = 'Signal'), 'Multicore snake', 50),
  ((select id from category where name = 'Signal'), 'Patch panel', 60)
on conflict (category_id, name) do nothing;

-- Playback
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Playback'), 'Media player', 10),
  ((select id from category where name = 'Playback'), 'Audio interface', 20),
  ((select id from category where name = 'Playback'), 'Laptop', 30),
  ((select id from category where name = 'Playback'), 'Tablet', 40),
  ((select id from category where name = 'Playback'), 'CD player', 50)
on conflict (category_id, name) do nothing;

-- Lighting - static
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Lighting - static'), 'LED par can', 10),
  ((select id from category where name = 'Lighting - static'), 'Wash light', 20),
  ((select id from category where name = 'Lighting - static'), 'Flood / city colour', 30),
  ((select id from category where name = 'Lighting - static'), 'Blinder', 40),
  ((select id from category where name = 'Lighting - static'), 'Strobe', 50),
  ((select id from category where name = 'Lighting - static'), 'Pixel bar / batten', 60),
  ((select id from category where name = 'Lighting - static'), 'Profile / theatre spot', 70),
  ((select id from category where name = 'Lighting - static'), 'Fresnel', 80)
on conflict (category_id, name) do nothing;

-- Lighting - moving
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Lighting - moving'), 'Moving head - spot', 10),
  ((select id from category where name = 'Lighting - moving'), 'Moving head - beam / sharpy', 20),
  ((select id from category where name = 'Lighting - moving'), 'Moving head - wash', 30),
  ((select id from category where name = 'Lighting - moving'), 'Moving head - hybrid', 40),
  ((select id from category where name = 'Lighting - moving'), 'Scanner', 50),
  ((select id from category where name = 'Lighting - moving'), 'Follow spot', 60)
on conflict (category_id, name) do nothing;

-- Lighting - effect
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Lighting - effect'), 'Derby / party effect', 10),
  ((select id from category where name = 'Lighting - effect'), 'Laser', 20),
  ((select id from category where name = 'Lighting - effect'), 'Mirror ball', 30),
  ((select id from category where name = 'Lighting - effect'), 'Mirror ball motor', 40),
  ((select id from category where name = 'Lighting - effect'), 'UV / blacklight', 50)
on conflict (category_id, name) do nothing;

-- Lighting - control
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Lighting - control'), 'Lighting console', 10),
  ((select id from category where name = 'Lighting - control'), 'DMX splitter', 20),
  ((select id from category where name = 'Lighting - control'), 'Dimmer pack', 30),
  ((select id from category where name = 'Lighting - control'), 'Wireless DMX', 40),
  ((select id from category where name = 'Lighting - control'), 'Hazer controller', 50),
  ((select id from category where name = 'Lighting - control'), 'Switch pack', 60)
on conflict (category_id, name) do nothing;

-- Visual
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Visual'), 'LED wall panel', 10),
  ((select id from category where name = 'Visual'), 'LED processor', 20),
  ((select id from category where name = 'Visual'), 'Projector', 30),
  ((select id from category where name = 'Visual'), 'Projection screen', 40),
  ((select id from category where name = 'Visual'), 'TV / monitor', 50),
  ((select id from category where name = 'Visual'), 'Video switcher', 60),
  ((select id from category where name = 'Visual'), 'Media server', 70),
  ((select id from category where name = 'Visual'), 'Camera', 80)
on conflict (category_id, name) do nothing;

-- Effects
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Effects'), 'Fog machine', 10),
  ((select id from category where name = 'Effects'), 'Haze machine', 20),
  ((select id from category where name = 'Effects'), 'Low fog / dry ice', 30),
  ((select id from category where name = 'Effects'), 'CO2 jet', 40),
  ((select id from category where name = 'Effects'), 'Cold spark', 50),
  ((select id from category where name = 'Effects'), 'Confetti blaster', 60),
  ((select id from category where name = 'Effects'), 'Bubble machine', 70),
  ((select id from category where name = 'Effects'), 'Snow machine', 80),
  ((select id from category where name = 'Effects'), 'Flame projector', 90)
on conflict (category_id, name) do nothing;

-- Truss
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Truss'), 'Box truss', 10),
  ((select id from category where name = 'Truss'), 'Ladder truss', 20),
  ((select id from category where name = 'Truss'), 'Circular truss', 30),
  ((select id from category where name = 'Truss'), 'Corner block', 40),
  ((select id from category where name = 'Truss'), 'Truss base plate', 50),
  ((select id from category where name = 'Truss'), 'Sleeve block', 60),
  ((select id from category where name = 'Truss'), 'Truss pin / clamp set', 70)
on conflict (category_id, name) do nothing;

-- Stand & rigging
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Stand & rigging'), 'Speaker stand / tripod', 10),
  ((select id from category where name = 'Stand & rigging'), 'Sub pole', 20),
  ((select id from category where name = 'Stand & rigging'), 'Lighting T-bar stand', 30),
  ((select id from category where name = 'Stand & rigging'), 'Manual winch stand', 40),
  ((select id from category where name = 'Stand & rigging'), 'Crank stand', 50),
  ((select id from category where name = 'Stand & rigging'), 'Hoist / chain motor', 60),
  ((select id from category where name = 'Stand & rigging'), 'G-clamp', 70),
  ((select id from category where name = 'Stand & rigging'), 'Safety wire', 80),
  ((select id from category where name = 'Stand & rigging'), 'Ratchet strap', 90)
on conflict (category_id, name) do nothing;

-- Stage
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Stage'), 'Stage deck', 10),
  ((select id from category where name = 'Stage'), 'Riser', 20),
  ((select id from category where name = 'Stage'), 'Stage skirting', 30),
  ((select id from category where name = 'Stage'), 'Stairs', 40),
  ((select id from category where name = 'Stage'), 'Railing', 50),
  ((select id from category where name = 'Stage'), 'Carpet / dance floor', 60)
on conflict (category_id, name) do nothing;

-- Power
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Power'), 'Generator', 10),
  ((select id from category where name = 'Power'), 'Distribution box', 20),
  ((select id from category where name = 'Power'), 'Extension board', 30),
  ((select id from category where name = 'Power'), 'Cable reel', 40),
  ((select id from category where name = 'Power'), 'UPS', 50),
  ((select id from category where name = 'Power'), 'Voltage stabiliser', 60),
  ((select id from category where name = 'Power'), 'Battery pack', 70)
on conflict (category_id, name) do nothing;

-- Cable
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Cable'), 'XLR cable', 10),
  ((select id from category where name = 'Cable'), 'Speakon cable', 20),
  ((select id from category where name = 'Cable'), 'Jack / TRS cable', 30),
  ((select id from category where name = 'Cable'), 'RCA cable', 40),
  ((select id from category where name = 'Cable'), 'DMX cable', 50),
  ((select id from category where name = 'Cable'), 'Power cable / IEC', 60),
  ((select id from category where name = 'Cable'), 'HDMI cable', 70),
  ((select id from category where name = 'Cable'), 'CAT / ethernet cable', 80),
  ((select id from category where name = 'Cable'), 'Adaptor / converter', 90)
on conflict (category_id, name) do nothing;

-- Backline - keys
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Backline - keys'), 'Synth / workstation', 10),
  ((select id from category where name = 'Backline - keys'), 'Stage piano', 20),
  ((select id from category where name = 'Backline - keys'), 'Keyboard amp', 30),
  ((select id from category where name = 'Backline - keys'), 'Keyboard stand', 40),
  ((select id from category where name = 'Backline - keys'), 'Keyboard bench', 50),
  ((select id from category where name = 'Backline - keys'), 'Sustain pedal', 60)
on conflict (category_id, name) do nothing;

-- Backline - drums
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Backline - drums'), 'Acoustic drum kit', 10),
  ((select id from category where name = 'Backline - drums'), 'Electronic drum kit', 20),
  ((select id from category where name = 'Backline - drums'), 'Cymbal set', 30),
  ((select id from category where name = 'Backline - drums'), 'Drum throne', 40),
  ((select id from category where name = 'Backline - drums'), 'Percussion - congas', 50),
  ((select id from category where name = 'Backline - drums'), 'Percussion - dholak / tabla', 60),
  ((select id from category where name = 'Backline - drums'), 'Octapad', 70),
  ((select id from category where name = 'Backline - drums'), 'Drum riser', 80)
on conflict (category_id, name) do nothing;

-- Backline - guitar
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Backline - guitar'), 'Electric guitar', 10),
  ((select id from category where name = 'Backline - guitar'), 'Acoustic guitar', 20),
  ((select id from category where name = 'Backline - guitar'), 'Bass guitar', 30),
  ((select id from category where name = 'Backline - guitar'), 'Guitar amp', 40),
  ((select id from category where name = 'Backline - guitar'), 'Bass amp', 50),
  ((select id from category where name = 'Backline - guitar'), 'Guitar stand', 60),
  ((select id from category where name = 'Backline - guitar'), 'Pedal board', 70)
on conflict (category_id, name) do nothing;

-- Backline - other
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Backline - other'), 'Music stand', 10),
  ((select id from category where name = 'Backline - other'), 'Music stand light', 20),
  ((select id from category where name = 'Backline - other'), 'Conductor podium', 30)
on conflict (category_id, name) do nothing;

-- Case & transport
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Case & transport'), 'Flight case', 10),
  ((select id from category where name = 'Case & transport'), 'Rack case', 20),
  ((select id from category where name = 'Case & transport'), 'Cable trunk', 30),
  ((select id from category where name = 'Case & transport'), 'Trolley / dolly', 40),
  ((select id from category where name = 'Case & transport'), 'Gig bag', 50),
  ((select id from category where name = 'Case & transport'), 'Speaker cover', 60),
  ((select id from category where name = 'Case & transport'), 'Tarpaulin', 70)
on conflict (category_id, name) do nothing;

-- Consumable
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Consumable'), 'Fog fluid', 10),
  ((select id from category where name = 'Consumable'), 'Haze fluid', 20),
  ((select id from category where name = 'Consumable'), 'CO2 cylinder', 30),
  ((select id from category where name = 'Consumable'), 'Gaffer tape', 40),
  ((select id from category where name = 'Consumable'), 'Cable tie', 50),
  ((select id from category where name = 'Consumable'), 'Battery', 60),
  ((select id from category where name = 'Consumable'), 'Gel / gobo', 70),
  ((select id from category where name = 'Consumable'), 'Spare lamp', 80)
on conflict (category_id, name) do nothing;

-- Tool & spare
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Tool & spare'), 'Tool kit', 10),
  ((select id from category where name = 'Tool & spare'), 'Multimeter', 20),
  ((select id from category where name = 'Tool & spare'), 'Spare part', 30),
  ((select id from category where name = 'Tool & spare'), 'Ladder', 40),
  ((select id from category where name = 'Tool & spare'), 'Torch', 50)
on conflict (category_id, name) do nothing;

-- Other
insert into subcategory (category_id, name, sort_order) values
  ((select id from category where name = 'Other'), 'Uncategorised', 10),
  ((select id from category where name = 'Other'), 'Sub-hired item', 20),
  ((select id from category where name = 'Other'), 'Sold / disposed', 30)
on conflict (category_id, name) do nothing;
