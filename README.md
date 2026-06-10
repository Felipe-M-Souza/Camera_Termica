# Vistoria Visual

Aplicativo Flutter para analise visual assistida por camera. A versao atual usa
imagem RGB do celular para realcar bordas, contraste, baixa luz simulada, mapa
termico simulado e areas escuras suspeitas.

## Escopo atual

- Captura stream da camera com o plugin `camera`.
- Processa frames YUV420 em uma etapa isolada da UI.
- Analisa a imagem original antes de aplicar filtros visuais.
- Carrega `assets/edge_detection.tflite` e roda inferencia periodica sobre o
  frame original para resumir a intensidade de bordas detectadas.
- Mostra filtros simulados apenas como visualizacao, sem afirmar leitura termica
  real.

## Limitacao importante

Celulares comuns nao capturam temperatura por pixel sem um sensor termico
dedicado. Para termografia real, o app precisara integrar hardware externo
como FLIR, Seek Thermal ou outro sensor compativel.

## Proximos passos sugeridos

- Treinar/substituir o modelo TFLite por um classificador real de manchas,
  rachaduras ou sinais de vazamento.
- Criar fluxo de vistoria com captura de fotos, anotacoes e relatorio.
- Adicionar controles avancados de camera via Android nativo/Camera2 quando o
  objetivo for explorar aparelhos como a linha Galaxy Ultra.
- Configurar assinatura release e identificador de pacote definitivo.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
```

## APK pelo GitHub Actions

O workflow `Android Debug APK` gera um APK debug automaticamente em pushes e
pull requests. Para baixar pelo celular:

1. Abra a aba **Actions** do repositorio no GitHub.
2. Entre na execucao mais recente de **Android Debug APK**.
3. Baixe o artifact `vistoria-visual-debug-apk`.
4. Extraia o ZIP e instale o `app-debug.apk` no Android.
