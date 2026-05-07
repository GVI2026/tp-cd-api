import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Application (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(new ValidationPipe());
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('GET /health', () => {
    it('retourne 200 avec status ok', () => {
      return request(app.getHttpServer())
        .get('/health')
        .expect(200)
        .expect((res) => {
          expect(res.body.status).toBe('ok');
          expect(res.body.timestamp).toBeDefined();
        });
    });
  });

  describe('GET /tasks', () => {
    it('retourne 200 avec un tableau', () => {
      return request(app.getHttpServer())
        .get('/tasks')
        .expect(200)
        .expect((res) => {
          expect(Array.isArray(res.body)).toBe(true);
        });
    });
  });

  describe('POST /tasks', () => {
    it('crée une tâche et retourne 201', () => {
      return request(app.getHttpServer())
        .post('/tasks')
        .send({ title: 'Tâche E2E', content: 'Test end-to-end', done: false })
        .expect(201)
        .expect((res) => {
          expect(res.body.id).toBeDefined();
          expect(res.body.title).toBe('Tâche E2E');
        });
    });

    it('retourne 400 si le titre est manquant', () => {
      return request(app.getHttpServer())
        .post('/tasks')
        .send({ content: 'sans titre' })
        .expect(400);
    });
  });
});
