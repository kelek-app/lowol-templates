<?php

namespace Tests\Feature;

use Tests\TestCase;

class ExampleTest extends TestCase
{
    public function test_the_status_page_answers_even_when_a_check_fails(): void
    {
        $this->get('/')
            ->assertOk()
            ->assertSee('version local')
            ->assertSee(['MySQL', 'Redis', 'Scheduler', 'Queue worker']);
    }
}
