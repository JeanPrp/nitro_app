// lib/service_catalog.dart
const List<String> kServiceTypes = [
  'Lavagem tradicional',
  'Lavagem detalhada',
  'Lavagem detalhada 2',
  'Lavagem detalhada 3',
  'Higinização',
  'Troca de feltros',
  'Revitalização de plásticos e borrachas',
  'Polimento',
  'Polimento de vidro',
  'Polimento de farol',
  'PPF',
  'Martelinho',
  'Vitrificação',
  'Outro',
];

/// Você pode colocar preço padrão aqui (se não quiser, deixa 0 e o vendedor define).
const Map<String, int> kDefaultPriceByService = {
  'Lavagem tradicional': 0,
  'Lavagem detalhada': 0,
  'Lavagem detalhada 2': 0,
  'Lavagem detalhada 3': 0,
  'Higinização': 0,
  'Troca de feltros': 0,
  'Revitalização de plásticos e borrachas': 0,
  'Polimento': 0,
  'Polimento de vidro': 0,
  'Polimento de farol': 0,
  'PPF': 0,
  'Martelinho': 0,
  'Vitrificação': 0,
  'Outro': 0,
};

/// Checklist de ENTRADA (risco + confirmação do que será feito)
const Map<String, String> kCheckInItems = {
  'photos': 'Fotos tiradas (externa + interna)',
  'scratches': 'Riscos/arranhões identificados e marcados',
  'dents': 'Amassados identificados',
  'glass': 'Trincas/lasca em vidro identificado',
  'wheels': 'Rodas com marcas / riscos',
  'interior': 'Interior com manchas/avarias registradas',
  'belongings': 'Pertences conferidos e anotados',
  'fuel': 'Combustível anotado',
  'confirm_services': 'Serviços confirmados com o cliente',
};

/// Checklist de SAÍDA (qualidade do serviço)
const Map<String, String> kCheckOutItems = {
  'wheels_ok': 'Rodas limpas',
  'paint_ok': 'Pintura sem marcas/manchas',
  'glass_ok': 'Vidros limpos',
  'interior_ok': 'Interior aspirado/limpo',
  'dash_ok': 'Painel/console/volante limpos',
  'mats_ok': 'Tapetes limpos e reposicionados',
  'tires_ok': 'Pretinho aplicado',
  'no_drips': 'Sem escorridos de água',
  'belongings': 'Pertences devolvidos',
  'evo_mats': 'Tapetes EVA posicionados',
  'steering_tape': 'Fita no volante colocada',
};