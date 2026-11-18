"""Build the versioned, bilingual content catalogue. No network required."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
rows = [
('core','Командный модуль','Command module','infrastructure',0,0,0,0,'dome','8ad5ce'),
('corridor','Гермокоридор','Pressure corridor','infrastructure',4,1,0,0,'corridor','97b1b4'),
('generator','Топливный генератор','Fuel generator','power',24,2,-48,0,'turbine','e4b477'),
('battery','Аккумулятор','Battery bank','power',18,2,0,0,'battery','dfb979'),
('oxygen','Кислородная станция','Oxygen station','life',22,3,9,0,'tanks','8ddbc2'),
('pump','Дренажный насос','Drainage pump','life',14,2,5,0,'pump','83b9d1'),
('warehouse','Склад','Storage bay','logistics',14,1,2,0,'cargo','b2c1ba'),
('dock','Док дронов','Drone dock','logistics',28,4,6,0,'dock','65c7d1'),
('mine','Добывающая установка','Mining rig','industry',20,2,10,0,'drill','d6aa73'),
('refinery','Переработчик','Alloy refinery','industry',25,3,12,0,'factory','d3ab81'),
('lab','Лаборатория','Research laboratory','science',28,4,8,2,'dome','a6b0e1'),
('relay','Ретранслятор','Relay station','science',30,3,5,0,'antenna','65d8cb'),
('habitat','Жилой модуль','Habitat','life',24,3,5,0,'dome','b7ccae'),
('oxygen_tank','Кислородный резервуар','Oxygen reservoir','life',18,2,1,0,'tanks','87cab4'),
('terminal','Грузовой терминал','Cargo terminal','logistics',26,3,6,0,'cargo','a7c8cc'),
('geothermal','Геотермальная станция','Geothermal plant','power',42,5,-85,0,'turbine','e1ac6d'),
('tidal','Турбина течения','Current turbine','power',30,3,-35,0,'turbine','8bc9dc'),
('chemical','Химический синтезатор','Chemical synthesizer','industry',32,4,14,0,'factory','b9cb87'),
('electronics','Электронная мастерская','Electronics workshop','industry',34,4,14,0,'factory','b5a3cf'),
('composite','Композитная мастерская','Composite workshop','industry',38,5,16,0,'factory','a8bdb4'),
('repair_shop','Ремонтная мастерская','Repair workshop','industry',28,3,8,0,'factory','dfbc87'),
('observatory','Пассивная обсерватория','Passive observatory','science',34,4,8,2,'dome','9bc0df'),
('silencer','Акустический экран','Acoustic screen','science',30,3,6,0,'antenna','80baa8'),
('beacon','Глубоководный маяк','Abyss beacon','science',60,8,18,2,'antenna','d6c4a4'),
]
modules={}
for i,(id,ru,en,cat,alloy,parts,power,crew,shape,color) in enumerate(rows):
    unlock = '' if i<12 else ['life_1','life_2','auto_1','energy_2','energy_1','life_3','auto_2','hull_2','auto_3','ocean_2','relay_2','relay_4'][i-12]
    modules[id]=dict(id=id,name_ru=ru,name_en=en,category=cat,cost={'alloy':alloy,'parts':parts},power=power,crew=crew,shape=shape,color=color,depth=850,capacity=220 if id in ('warehouse','terminal','core') else 50,build_time=7+i%4,unlock=unlock)
branches=[('hull','Корпуса','Pressure hulls',['Усиленные оболочки','Композитная броня','Абиссальная защита','Умные переборки','Сейсмозащита','Живучесть'],['Reinforced shells','Composite armor','Abyss protection','Smart bulkheads','Seismic isolation','Resilience']),('energy','Энергетика','Power systems',['Турбины течения','Геотермальная энергия','Ёмкие батареи','Умная сеть','Экономичный синтез','Резервирование'],['Current turbines','Geothermal power','Dense batteries','Smart grid','Efficient synthesis','Redundancy']),('auto','Автономность','Autonomy',['Грузовые терминалы','Микроэлектроника','Ремонтные системы','Тихие двигатели','Дальние маршруты','Автономные рои'],['Cargo terminals','Microelectronics','Repair systems','Silent engines','Long routes','Autonomous swarms']),('ocean','Океанология','Oceanography',['Анализ образцов','Пассивное наблюдение','Глубинная биология','Сонография','Экосистемы','Расшифровка сигнала'],['Sample analysis','Passive observation','Deep biology','Sonography','Ecosystems','Signal decoding']),('relay','Связь','Relay network',['Донная связь','Акустические экраны','Релейные протоколы','Глубоководный маяк','Помехоустойчивость','Последний сигнал'],['Seabed link','Acoustic screens','Relay protocols','Deep beacon','Noise rejection','The final signal'])]
research=[]
for branch,ru,en,names,eng in branches:
    for n,(name,ename) in enumerate(zip(names,eng),1):
        research.append(dict(id=f'{branch}_{n}',name_ru=name,name_en=ename,branch=branch,branch_ru=ru,branch_en=en,cost=12+n*9,duration=12+n*6,requires=[] if n==1 else [f'{branch}_{n-1}']))
# Life support shares the hull tree's progression through explicit unlock aliases in simulation.
sectors=[('shelf','Край шельфа','Shelf edge',320,'4c9d9a'),('slope','Континентальный склон','Continental slope',1100,'4b83a0'),('vents','Геотермальное поле','Hydrothermal field',2200,'b3936b'),('abyss','Абиссальная равнина','Abyssal plain',4100,'6a6f9b')]
sectors=[dict(id=id,name_ru=ru,name_en=en,depth=d,color=c) for id,ru,en,d,c in sectors]
finds=[('Фрагмент обсерватории','Observatory fragment'),('Светящаяся колония','Luminous colony'),('Чёрный ящик','Black box'),('Кремниевый скелет','Silica skeleton'),('Старая донная линия','Old seabed cable'),('Поющая губка','Singing sponge'),('Затонувший зонд','Sunken probe'),('Архив экспедиции','Expedition archive'),('Хемосинтетическая колония','Chemosynthetic colony'),('Термальный кристалл','Thermal crystal'),('След миграции','Migration trace'),('Сеть микрофиламентов','Microfilament network'),('Глубинная линза','Deep lens'),('Фрагмент карты','Chart fragment'),('Забытый ретранслятор','Forgotten relay'),('Абиссальный цветок','Abyssal bloom'),('Сердце обсерватории','Observatory heart'),('Источник сигнала','Signal source')]
for n, sector in enumerate(sectors):
    sector['deposits']=[dict(cell=cell, amount=600+n*200) for cell in [[2,0],[3,-3],[-5,2],[5,4]]]
    sector['vents']=[[4,-2],[-4,3]] if n==2 else []
findings=[]
for i,(ru,en) in enumerate(finds):
    sector=0 if i<4 else 1 if i<9 else 2 if i<13 else 3
    findings.append(dict(id=f'find_{i}',name_ru=ru,name_en=en,sector=sector,cell=[[5,-3],[-5,-4],[4,5],[-4,5],[7,2]][i%5],data=12+sector*6,samples=2+sector,lore_ru='Запись обсерватории подтверждает: сигнал повторяется между станциями. Образец поможет восстановить сеть.' if i%2==0 else 'Датчики зафиксировали необычную реакцию на шум. Тихое наблюдение раскрывает больше, чем активное сканирование.',lore_en='An observatory record confirms that the signal repeats between stations. This sample will help restore the network.' if i%2==0 else 'Sensors recorded an unusual response to noise. Quiet observation reveals more than active scanning.'))
story=json.loads((ROOT/'scripts/story_content.json').read_text())
for finding,(ru,en) in zip(findings,story):
    finding['lore_ru']=ru;finding['lore_en']=en
names=[('Плановое снабжение','Routine supply','alloy',20),('Ремонтный резерв','Repair reserve','parts',8),('Минеральный анализ','Mineral survey','ore',30),('Тихое исследование','Quiet research','data',20),('Образцы шельфа','Shelf samples','samples',3),('Оптические системы','Optical systems','quartz',15),('Корпус следующей станции','Next station hull','alloy',40),('Автономный комплекс','Autonomous complex','electronics',8),('Биология глубин','Deep biology','samples',6),('Усиление сети','Network reinforcement','composite',8),('Архив океана','Ocean archive','data',65),('Последняя доставка','Final delivery','alloy',70)]
contracts=[dict(id=f'contract_{i}',name_ru=ru,name_en=en,resource=res,amount=amount,credits=40+i*12,data=5+i*2) for i,(ru,en,res,amount) in enumerate(names)]
contract_types={1:('repair',1),2:('survey',2),3:('quiet',45),6:('relay',2),7:('research',6),8:('survey',10),10:('uptime',180)}
for i,c in enumerate(contracts):
    c['kind'],c['target']=contract_types.get(i,('delivery',c['amount']))
events=[]
for kind,rus,ens in [('leak',['Микропротечка','Трещина оболочки','Износ уплотнителя','Повреждение стыка','Разгерметизация','Глубинная трещина'],['Microleak','Hull crack','Worn seal','Joint damage','Depressurization','Pressure fracture']),('power',['Перегрузка линии','Сбой преобразователя','Повреждение кабеля','Замыкание','Сбой регулятора','Падение мощности'],['Line overload','Converter fault','Cable damage','Short circuit','Regulator fault','Power loss']),('current',['Донное течение','Облако взвеси','Дальний шторм','Сдвиг течения','Сейсмическая рябь','Плотная взвесь'],['Seabed current','Silt cloud','Distant storm','Current shift','Seismic ripple','Dense sediment']),('bio',['Стая у датчиков','Обрастание антенны','Песня глубин','Крупный силуэт','Миграция планктона','Акустический резонанс'],['School near sensors','Antenna fouling','Song of the deep','Large silhouette','Plankton migration','Acoustic resonance'])]:
    for j,(ru,en) in enumerate(zip(rus,ens)):
        events.append(dict(id=f'{kind}_{j}',kind=kind,name_ru=ru,name_en=en,warning=16+j*2,duration=35+j*5))
resources={'alloy':['Сплав','Alloy'],'ore':['Руда','Ore'],'parts':['Ремкомплекты','Repair kits'],'fuel':['Топливо','Fuel'],'data':['Данные','Data'],'quartz':['Кварц','Quartz'],'electronics':['Электроника','Electronics'],'samples':['Образцы','Samples'],'composite':['Композит','Composite']}
data=dict(version=1,modules=modules,research=research,sectors=sectors,findings=findings,contracts=contracts,events=events,resources=resources,creatures=['lanternfish','jellyfish','ray','whale','siphonophore','squid','tube_worm','abyss_bloom'])
def english_catalog(value):
    """Ship English content only; authoring references never enter the game pack."""
    if isinstance(value, dict):
        return {key: english_catalog(item) for key, item in value.items() if not key.endswith('_ru')}
    if isinstance(value, list):
        return [english_catalog(item) for item in value]
    return value
data = english_catalog(data)
data['resources'] = {key: labels[1] for key, labels in resources.items()}
(ROOT/'game/assets/content.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print(f'Catalogue: {len(modules)} modules, {len(research)} research, {len(events)} events, {len(findings)} discoveries')
