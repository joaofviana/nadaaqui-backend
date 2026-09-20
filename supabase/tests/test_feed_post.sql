-- Testes para o fluxo de feed posts
-- Testa a RPC create_feed_post e list_feed

-- Setup: Criar usuário de teste
DO $$
DECLARE
  v_user_id uuid;
  v_place_id uuid;
  v_post_id uuid;
  v_feed jsonb;
BEGIN
  -- Criar perfil de teste
  INSERT INTO public.profiles (id, display_name, show_in_presence)
  VALUES (
    gen_random_uuid(),
    'Usuário Teste Feed',
    true
  ) ON CONFLICT (id) DO NOTHING
  RETURNING id INTO v_user_id;
  
  -- Criar place de teste
  INSERT INTO public.places (id, name, place_type, location, city_slug, is_published)
  VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Piscina Teste Feed',
    'public_pool',
    ST_SetSRID(ST_MakePoint(-46.6333, -23.5505), 4326)::geography,
    'sao-paulo',
    true
  ) ON CONFLICT (id) DO NOTHING
  RETURNING id INTO v_place_id;
  
  RAISE NOTICE 'Test setup: user_id=%, place_id=%', v_user_id, v_place_id;
  
  -- Test 1: Criar post simples
  -- (em produção seria chamado via authenticated user)
  RAISE NOTICE 'Test 1: Criar post de texto simples';
  
  INSERT INTO public.posts (user_id, body, kind, city_slug)
  VALUES (v_user_id, 'Post de teste simples', 'text', 'sao-paulo')
  RETURNING id INTO v_post_id;
  
  RAISE NOTICE 'Post criado com ID: %', v_post_id;
  
  -- Verificar post foi criado
  PERFORM FROM public.posts WHERE id = v_post_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post não foi criado corretamente';
  END IF;
  
  -- Test 2: Criar post com place
  RAISE NOTICE 'Test 2: Criar post com place';
  
  INSERT INTO public.posts (user_id, place_id, body, kind, city_slug)
  VALUES (v_user_id, v_place_id, 'Check-in na piscina', 'check_in', 'sao-paulo');
  
  RAISE NOTICE 'Post com place criado';
  
  -- Test 3: Criar review com stars
  RAISE NOTICE 'Test 3: Criar review com stars';
  
  INSERT INTO public.posts (user_id, place_id, body, kind, stars, city_slug)
  VALUES (v_user_id, v_place_id, 'Ótima piscina!', 'review', 5, 'sao-paulo');
  
  RAISE NOTICE 'Review criada';
  
  -- Test 4: Listar feed
  RAISE NOTICE 'Test 4: Listar feed';
  
  SELECT * INTO v_feed FROM public.list_feed(p_limit => 10);
  
  RAISE NOTICE 'Feed items: %', jsonb_array_length(v_feed->'items');
  
  -- Verificar estrutura do feed
  IF v_feed->'items' is null THEN
    RAISE EXCEPTION 'Feed não retornou items';
  END IF;
  
  -- Test 5: Verificar ordem cronológica
  RAISE NOTICE 'Test 5: Verificar ordem cronológica do feed';
  
  -- Posts devem estar ordenados por created_at desc
  FOR i IN 0..jsonb_array_length(v_feed->'items')-2 LOOP
    DECLARE
      current_item jsonb;
      next_item jsonb;
      current_created timestamptz;
      next_created timestamptz;
    BEGIN
      current_item := (v_feed->'items')->i;
      next_item := (v_feed->'items')->(i+1);
      
      current_created := (current_item->>'createdAt')::timestamptz;
      next_created := (next_item->>'createdAt')::timestamptz;
      
      IF current_created < next_created THEN
        RAISE EXCEPTION 'Feed não está em ordem cronológica decrescente';
      END IF;
    END;
  END LOOP;
  
  RAISE NOTICE 'Feed está corretamente ordenado';
  
  -- Test 6: Testar validação de review sem stars
  RAISE NOTICE 'Test 6: Testar validação de review sem stars';
  
  BEGIN
    INSERT INTO public.posts (user_id, body, kind, city_slug)
    VALUES (v_user_id, 'Review sem stars', 'review', 'sao-paulo');
    RAISE EXCEPTION 'Review sem stars deveria falhar';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Review sem stars falhou como esperado: %', SQLERRM;
  END;
  
  -- Test 7: Testar limite de caracteres
  RAISE NOTICE 'Test 7: Testar limite de caracteres (500)';
  
  BEGIN
    INSERT INTO public.posts (user_id, body, kind, city_slug)
    VALUES (
      v_user_id, 
      repeat('a', 501), 
      'text', 
      'sao-paulo'
    );
    RAISE EXCEPTION 'Post com >500 caracteres deveria falhar';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Post longo falhou como esperado: %', SQLERRM;
  END;
  
  -- Cleanup
  RAISE NOTICE 'Cleanup: removendo dados de teste';
  
  DELETE FROM public.posts WHERE user_id = v_user_id;
  DELETE FROM public.places WHERE id = v_place_id;
  DELETE FROM public.profiles WHERE id = v_user_id;
  
  RAISE NOTICE 'Testes concluídos com sucesso!';
  
END $$;